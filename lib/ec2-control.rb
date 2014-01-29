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
    # parse arguments
    cli_arguments = CliArgumentParser.parse

    # instance replaces 'new' method for singleton class..
    @config = Config.instance

    @config.create(cli_arguments)

    @config.display if $VERBOSE
    exit

    ## check whether hostname and domain were specified by the user or are in the config file
    hostname, domain, new_records = establish_hostname_and_domain(config, subcommand_parameters)

    #
    # UserData handling
    # 

    # NOTE: establish the user_data
    # NOTE: open template, resolve template, JOIN template with user_data..

    # decide whether to be verbose based on cli args or default in-app setting
    $VERBOSE = global_parameters.verbose

    ## establish what user_data will be passed into the cloud instance
    # user_data = UserData.configure_user_data(config, subcommand_parameters)

    erb, merged_user_data_template_variables = merge_variables_for_user_data_template(config, subcommand_parameters)

    if subcommand_parameters.user_data_template_variables
      user_data_template_resolved = resolve_template(erb, merged_user_data_template_variables)
    end

    show_parsed_template(subcommand_parameters, user_data_template_resolved)

    user_data = combine_user_data(subcommand_parameters, user_data_template_resolved)

    #
    # ec2 / route53
    # 

    # NOTE: create ec2 instance with DNS

    ## initialize AWS object with credentials from config file
    initialize_aws_with_credentials(config)

    ## initialize ec2 object with credentials
    ec2 = initialize_ec2_instance(config, subcommand_parameters)


    ## check whether DNS records already exist..
    record_sets = check_hostname_and_domain_availability(config, hostname, domain, new_records)

    instance = create_instance(config, ec2, subcommand_parameters, user_data)

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
