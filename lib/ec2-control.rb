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
    @config.display if $VERBOSE

    # load erb template and parse the template with user_data_template_variables
    # then merge user_data template with raw user_data (if provided) -
    # end up single user_data ready to pass into ec2 instance..
    @user_data = UserData.instance
    @user_data.create(@config)
    @user_data.display if $VERBOSE or @config[:show_parsed_template]


    #
    # aws interaction
    # 

    AWS::Route53.check_hostname_and_domain_availability(@config)

    exit
    # NOTE: create ec2 instance with DNS

    ## initialize ec2 object with credentials
    #ec2 = AWS.initialize_ec2_instance(config, subcommand_parameters)

    instance = create_instance(config, ec2, subcommand_parameters, user_data)

    # FIXME: add to route53 stuff..

    #@config[:route53] ||= {}

    #@config[:route53][:new_dns_records] = {
    #  :public  => { :alias => "#{hostname}.#{domain}.",         :target => nil },
    #  :private => { :alias => "#{hostname}-private.#{domain}.", :target => nil }
    #}

    update_route53(instance, config, hostname, domain, new_records, record_sets)

    #
    # summary
    # 

    show_instance_details(instance, new_records, hostname, domain)
  end

  def self.show_instance_details(instance, new_records, hostname, domain)
    puts <<-HEREDOC.strip_heredoc
      # instance details:
      id:               #{instance.id}
      public ip:        #{instance.public_ip_address}
      public aws fqdn:  #{instance.public_dns_name}
      private ip:       #{instance.private_ip_address}
      private aws fqdn: #{instance.private_dns_name}
    HEREDOC

    unless hostname.nil? or domain.nil?
      puts <<-HEREDOC.strip_heredoc
        public fqdn:      #{new_records[:public][:alias]}
        private fqdn:     #{new_records[:private][:alias]}
      HEREDOC
    end

    puts <<-HEREDOC.strip_heredoc
      
      # connect: 
      ssh #{instance.dns_name} -l ubuntu
    HEREDOC
  end
end
