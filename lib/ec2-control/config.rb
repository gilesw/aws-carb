#!/usr/bin/env ruby

require 'aws-sdk'
require 'yaml'
require 'erubis'
require 'awesome_print'
require 'securerandom'
require 'shell-spinner'
require 'active_support/core_ext/string/strip'
require 'ostruct'
require 'subcommand'
require 'colorize'
require 'singleton'

include Subcommands

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
  class Config
    include Singleton

    def initialize
      @config         = OpenStruct.new
      @config.ec2     = OpenStruct.new
      @config.general = OpenStruct.new
      @config.route53 = OpenStruct.new

      load_file(global_parameters.config_file)
      load_user_data_template_variables(user_data_template_variables)

    end

    def self.load_file(config_file)
      begin
        @config.config_file = YAML.load_file(config_file)
      rescue => e
        puts "# failed to load config file: '#{config_file}'"
        die e
      end
    end

    # for template_variables only..
    def self.load_defaults_from_config_file(config, subcommand_parameters)

      # NOTE: not all 'subcommand parameters' are ec2 parameters - a few of them are used elsewhere.

      # presedence of config values is as follows:
      # 
      # config file[common] < config file [specific] < command line argument
      #
      # unfortunately we start off with a struct full of command line argument values since the config
      # file location isnt finalised until after the cli args have been parsed.

      general_parameters = [ :user_data_template, :user_data_template_variables, :show_parsed_template ]

      general_parameters.each do |parameter|
        @config.general.method(parameter) = config['general'][parameter.to_s] if config['general'] and config['general'][parameter.to_s]
      end

      ec2_available_parameters = [
        :image_id, :instance_type, :key_name, :user_data, :iam_instance_profile,
        :availability_zone, :security_group_ids, :subnet, :private_ip_address,
        :dedicated_tenancy, :disable_api_termination, :instance_initiated_shutdown_behavior,
        :ebs_optimized, :monitoring_enabled
      ]

      ec2_available_parameters.each do |parameter|
        @config.ec2.method(parameter) = config['ec2'][parameter.to_s] if config['ec2'] and config['ec2'][parameter.to_s]
      end

      # FIXME
      #
      # http://docs.aws.amazon.com/AWSRubySDK/latest/AWS/EC2/InstanceCollection.html
      #
      # ec2_params = {}
      #ec2_parameters.each do |key, value|
      #  ec2_params[key.to_sym] = value
      #end
      #  :image_id      => subcommand_parameters.image_id,
      #  :instance_type => subcommand_parameters.instance_type,
      #  :key_name      => subcommand_parameters.key_name,
      #  :user_data     => user_data,

      ec2_parameters = {
        :image_id                             => subcommand_parameters.image_id,
        :instance_type                        => subcommand_parameters.instance_type,
        :key_name                             => subcommand_parameters.key_name,
        :user_data                            => user_data,
        :iam_instance_profile                 => subcommand_parameters.iam_instance_profile,
        :monitoring_enabled                   => subcommand_parameters.monitoring_enabled,
        :security_groups                      => subcommand_parameters.security_groups,
        :security_group_ids                   => subcommand_parameters.security_group_ids,
        :disable_api_termination              => subcommand_parameters.disable_api_termination,
        :instance_initiated_shutdown_behavior => subcommand_parameters.instance_initiated_shutdown_behavior,
        :subnet                               => subcommand_parameters.subnet,
        :private_ip_address                   => subcommand_parameters.private_ip_address,
        :ebs_optimized                        => subcommand_parameters.ebs_optimized,
        :availability_zone                    => subcommand_parameters.availability_zone,
        :dedicated_tenancy                    => subcommand_parameters.dedicated_tenancy,
      }

      ec2_parameters.delete_if { |key, value| value.nil? }

      return ec2_parameters, general_parameters
    end

    # try and work out the hostname, presidence is:
    #
    # * config file
    # * user_data_template_variables cli args
    # 
    # note: raw user_data is not checked (not to be confused with user_data_template or user_data_template_variables..)
    #
    def self.establish_hostname_and_domain(config, subcommand_parameters)

      hostname, domain = nil

      ShellSpinner "# checking whether hostname and domain have been set", false do
        if config['common']
          hostname = config['common']['hostname'] if config['common']['hostname']
          domain   = config['common']['domain']   if config['common']['domain']
        end

        if config['route53']
          hostname = config['route53']['hostname'] if config['route53']['hostname']
          domain   = config['route53']['domain']   if config['route53']['domain']
        end

        if subcommand_parameters.user_data_template_variables
          user_data_template_variables = eval(subcommand_parameters.user_data_template_variables)

          hostname = user_data_template_variables[:hostname] unless user_data_template_variables[:hostname].nil?
          domain   = user_data_template_variables[:domain]   unless user_data_template_variables[:domain].nil?
        end
      end

      puts

      if domain.nil? and hostname.nil?
        debug "# WARNING: hostname and domain not found in config file and/or user_data_template_arguments"
        debug "#          route53 dynamic DNS will not be updated!"
        debug
      elsif domain and hostname.nil?
        debug "# WARNING: hostname not found in config file or user_data_template_arguments."
        debug "#          a random hostname will be picked for your instance and route53"
        debug "#          dynamic dns will not be updated"
        debug
      elsif domain.nil? and hostname
        debug "# WARNING: domain not found in config file or user_data_template_arguments."
        debug "#          route53 dynamic dns will not be updated"
        debug
      else
        debug "# found hostname and domain:"
        debug "hostname: #{hostname}"
        debug "domain:   #{domain}"
        debug
      end

      new_records = {
        :public  => { :alias => "#{hostname}.#{domain}.",         :target => nil },
        :private => { :alias => "#{hostname}-private.#{domain}.", :target => nil }
      }

      return hostname, domain, new_records
    end

    # we somewhat stupidly have the option of parsing in a hash of variables that can be used in our user_data_template
    # this method tests to see if the parameters value successfully evaluates to a hash
    # NOTE: perhaps this would be better if it were a set of key:values..
    def self.load_user_data_template_variables(user_data_template_variables)

      return unless user_data_template_variables

      begin
        config = eval(user_data_template_variables)

        raise ArguementError, "could not parse user_data_template_variables: '#{user_data_template_variables}'" unless config.class == Hash

        @config.user_data_template_variables = config
      rescue => e
        puts "# failed to parse user_data_template_variables, is your string properly quoted?"
        die e
      end
    end

    # variables to be used in your template can come from the following places:
    # 
    #  * config file: 'common' section
    #  * config file: 'template_variables:' section
    #  * cli args:     'user_data_template_variables'
    # 
    # in terms of precedence, the following applies:
    # 
    #   common < template_variables < user_data_template_variables
    # 
    def self.merge_variables_for_user_data_template(config, subcommand_parameters)
      if subcommand_parameters.user_data_template.nil?
        debug "# no user_data_template specified"
        debug
        return
      else
        debug "# user_data_template specified"
        debug
      end

      puts

      begin
        debug "# loading template into erubis"
        erb = Erubis::Eruby.new(File.read(subcommand_parameters.user_data_template))
        debug
      rescue => e
        puts "# failed to load template: #{subcommand_parameters.user_data_template}"
        die e
      end

      puts "# attempting to merge variables from config file and user_data_template_variables cli argument value"
      puts

      # create a new hash with variables to pass to template.. merge
      # variables in order of presedence as described above.
      user_data_template_variables_merged = {}

      if config['common'].nil?
        puts "# no 'common' section found in config file"
        puts
      else
        puts "# merging config 'common':"
        ap config['common']
        user_data_template_variables_merged.merge!(config['common'])
      end

      puts

      if config['template_variables'].nil?
        puts "# no 'template_variables' section found in config file"
        puts
      else
        puts "# merging config 'template_variables':"
        ap config['template_variables']
        user_data_template_variables_merged.merge!(config['template_variables'])
      end

      puts

      if subcommand_parameters.user_data_template_variables.nil?
        puts "# no user_data_template_variables given.."
        puts
      else
        puts "# merging cli arg 'user_data_template_variables':"
        ap eval(subcommand_parameters.user_data_template_variables)
        user_data_template_variables_merged.merge!(eval(subcommand_parameters.user_data_template_variables))
      end

      puts

      puts "# resulting merged user_data template variable hash:"
      ap user_data_template_variables_merged
      puts

      return erb, user_data_template_variables_merged
    end

    def self.display(subcommand_parameters)
      puts "# EC2 instance options:"

      # FIXME: align variables in a column..
      keys        = subcommand_parameters.marshal_dump.group_by(&:size).max
      longest_key = keys[1][keys[0]][0].length

      subcommand_parameters.marshal_dump.each do |key, value|

        next if value.nil?
        next if String(value).empty?

        puts "#{key}:".to_s.ljust(longest_key + 2) + "#{value}" unless value.nil?
      end

      puts
    end
  end
end
