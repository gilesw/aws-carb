#!/usr/bin/env ruby

require 'aws-sdk'
require 'yaml'
require 'erubis'
require 'awesome_print'
require 'securerandom'
require 'shell-spinner'
require 'active_support'
require 'active_support/core_ext'
require 'active_support/core_ext/hash'
require 'active_support/hash_with_indifferent_access'
require 'active_support/core_ext/string/strip'
require 'active_support/core_ext/hash/keys'
require 'ostruct'
require 'subcommand'
require 'singleton'
require 'andand'
require 'colorize'

require 'aws-carb/user_data'
require 'aws-carb/monkey_patches'
require 'aws-carb/config'
require 'aws-carb/version'
require 'aws-carb/cli_argument_parser'
require 'aws-carb/helpers'
require 'aws-carb/services/route53'
require 'aws-carb/services/ec2'

include ActiveSupport

# module is broken up into:
#
# AWSCarb.*                  - main methods
# AWSCarb::CliArugmentParser - argument parsing
# AWSCarb::Config            - argument checking / config checking
# AWSCarb::UserData          - parse user data template and possibly combine with user_data cli arg
# AWSCarb::Services::Ec2     - build an ec2 instance
# AWSCarb::Services::Route53 - create dns records in route53
#

if ! $stdout.tty?
  String.class_eval do
    def colorize(args)
      self
    end
  end
end

module AWSCarb
  def self.banner
    banner = <<-HEREDOC.strip_heredoc

       ::::::::      :::     :::::::::  :::::::::  
      :+:    :+:   :+: :+:   :+:    :+: :+:    :+: 
      +:+         +:+   +:+  +:+    +:+ +:+    +:+ 
      +#+        +#++:++#++: +#++:++#:  +#++:++#+  
      +#+        +#+     +#+ +#+    +#+ +#+    +#+ 
      #+#    #+# #+#     #+# #+#    #+# #+#    #+# 
       ########  ###     ### ###    ### #########  

          - cloudinit and route53 bootstrap -

    HEREDOC

    indent = ' ' * 6

    puts banner.each_line.map { |line| indent + line }
  end

  def self.run

    #
    # configuration
    #

    # parse cli args
    cli_arguments = CliArgumentParser.parse

    # display banner on successful cli argument parsing..
    banner

    # create a configuration based on our various data sources..
    @config = Config.instance
    @config.create(cli_arguments)
    @config.display if $GLOBAL_VERBOSE

    # load erb template and parse the template with user_data_template_variables
    # then merge user_data template with raw user_data (if provided) -
    # end up single user_data ready to pass into ec2 instance..
    @user_data = UserData.instance

    combined_user_data = @user_data.create(@config)

    @config.config[:ec2][:user_data] = combined_user_data

    @user_data.display if @config[:user_data_template][:file] and ($GLOBAL_VERBOSE or @config[:show_parsed_template])

    #
    # aws interaction
    # 
    if @config[:route53].andand[:new_dns_records]
      @route53 = Services::Route53.instance
      @route53.client(@config)
      @route53.check_hostname_and_domain_availability
    end

    ## initialize ec2 object with credentials
    @ec2 = Services::Ec2.instance
    @ec2.client(@config)
    @ec2.create_instance

    if @config[:route53].andand[:new_dns_records]
      @route53.create_records(@ec2)
    end

    #
    # summary
    # 

    show_instance_details
  end

  def self.show_instance_details
    puts <<-HEREDOC.strip_heredoc
      # instance details:
      id:               #{@ec2.instance.id}
      public ip:        #{@ec2.instance.public_ip_address}
      public aws fqdn:  #{@ec2.instance.public_dns_name}
      private ip:       #{@ec2.instance.private_ip_address}
      private aws fqdn: #{@ec2.instance.private_dns_name}
    HEREDOC

    unless @config[:route53][:new_dns_records].nil?
      puts <<-HEREDOC.strip_heredoc
        public fqdn:      #{@config[:route53][:new_dns_records][:public][:alias]}
        private fqdn:     #{@config[:route53][:new_dns_records][:private][:alias]}
      HEREDOC
    end

    puts <<-HEREDOC.strip_heredoc
      
      # connect: 
      ssh #{@ec2.instance.dns_name} -l ubuntu
    HEREDOC
  end
end
