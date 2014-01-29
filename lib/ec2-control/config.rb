#!/usr/bin/env ruby

module Ec2Control
  class Config
    include Singleton

    attr_reader :config

    def initialize(cli_arguments)

      @config = Config.load_file(cli_arguments.global.config_file)

      merge_cli_arguments_with_config

      establish_hostname_and_domain
    end

    def merge_cli_arguments_with_config
      begin

        # merge the config overrides into config
        cli_arguments.subcommand.config_overrides.marshal_dump.each do |key, value|
          if @config.send(key.to_s)
            @config.send(key.to_s).merge cli_arguements.subcommand.config_overrides.send("#{key}_variables")
          end
        end

        # merge the convenience argument parameters with config
        @config.common.merge                       cli_arguements.subcommand.common.marshal_dump
        @config.general.merge                      cli_arguements.subcommand.general.marshal_dump
        @config.ec2.merge                          cli_arguements.subcommand.ec2.marshal_dump
        @config.route53.merge                      cli_arguements.subcommand.route53.marshal_dump
        @config.user_data_template_variables.merge cli_arguements.subcommand.user_data_template_variables.marshal_dump

      rescue => e
        puts "# failed to merge override hash for: #{key}"
        die e
      end
    end

    def load_file(cli_argument_config_file)

      if cli_argument_config_file
        config_file = cli_argument_config_file
      else
        config_file = 'config.yaml'
      end

      begin
        # make keys symbols so we can more easily merge with cli arg structs..
        @config = YAML.load_file(config_file).deep_symbolize_keys
      rescue => e
        puts "# failed to load config file: '#{config_file}'"
        die e
      end
    end

    # when looking for a key, check 'common' section first, then override if a value
    # in the supplied context is found..
    def find_with_context(key, context) 
      return @config.send(context)[key] if @config.send(context)[key]
      return @config.common[key]        if @config.common[key]
      return nil
    end

    def [](key, context)
      @config[key]
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

        hostname = @config.find_with_context(:hostname, :user_data_template_variables)
        domain   = @config.find_with_context(:domain,   :user_data_template_variables)
        hostname = @config.find_with_context(:hostname, :route53)
        domain   = @config.find_with_context(:domain, :route53)

        help = <<-HEREDOC.strip_heredoc
          #       
          #         checked:
          #          'common', 'user_data_template_variables',
          #          and 'route53' sections of config
          #          --common-variables, --route53-variables,
          #          and --user-data-template-variables
          #
          #          route53 dynamic DNS will not be updated!
        HEREDOC

        if domain.nil? and hostname.nil?
          debug "# WARNING: hostname and domain not found"
          debug help
        elsif domain and hostname.nil?
          debug "# WARNING: hostname not found"
          debug help
        elsif domain.nil? and hostname
          debug "# WARNING: domain not found"
          debug help
        else
          debug "# found hostname and domain:"
          debug "hostname: #{hostname}"
          debug "domain:   #{domain}"
          debug

          @config.new_records = {
            :public  => { :alias => "#{hostname}.#{domain}.",         :target => nil },
            :private => { :alias => "#{hostname}-private.#{domain}.", :target => nil }
          }
        end
      end
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
