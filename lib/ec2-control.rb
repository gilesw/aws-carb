#!/usr/bin/env ruby

require 'aws-sdk'
require 'yaml'
require 'erubis'
require 'awesome_print'
require 'securerandom'
require 'shell-spinner'
require 'active_support/core_ext/string/strip'
require 'active_support/core_ext/hash/keys'
require 'ostruct'
require 'subcommand'
require 'colorize'
require 'singleton'
require 'andand'

# * list stuff
# * terminate stuff
# * turn off spinner if not a tty?

# module is broken up into:
#
# Ec2Control.*                  - main methods
# Ec2Control::CliArugmentParser - argument parsing
# Ec2Control::Config            - argument checking / config checking
# Ec2Control::UserData          - parse user data template and possibly combine with user_data cli arg
# Ec2Control::AWS::Ec2          - build an ec2 instance
# Ec2Control::AWS::Route53      - create dns records in route53
#

module Ec2Control
  def self.run

    #
    # configuration
    #

    # parse cli args
    cli_arguments = CliArgumentParser.parse

    # create a configuration based on our various data sources..
    @config = Config.instance
    @config.create(cli_arguments)
    @config.display if $GLOBAL_VERBOSE

    # load erb template and parse the template with user_data_template_variables
    # then merge user_data template with raw user_data (if provided) -
    # end up single user_data ready to pass into ec2 instance..
    @user_data = UserData.instance
    @user_data.create(@config)
    @user_data.display if @config[:user_data_template][:file] and ($GLOBAL_VERBOSE or @config[:show_parsed_template])


    #
    # aws interaction
    # 

    if @config[:route53].andand[:new_dns_records]
      @route53 = AmazonWebServices::Route53.instance
      @route53.client(@config)
      @route53.check_hostname_and_domain_availability
    end

    ## initialize ec2 object with credentials
    @ec2 = AmazonWebServices::Ec2.instance
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
