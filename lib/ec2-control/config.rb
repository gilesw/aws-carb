#!/usr/bin/env ruby

module Ec2Control
  class Config
    include Singleton

    attr_reader :config

    def create(cli_arguments)

      @config = load_file(cli_arguments.global.config_file)

      merge_cli_arguments_with_config(cli_arguments)

      establish_hostname_and_domain
    end

    def merge_cli_arguments_with_config(cli_arguments)
      begin

        config_sections = [:common, :general, :ec2, :route53, :user_data_template_variables, :user_data_template]
        # all sections share 'common' variables..
        config_sections.each do |section|
          @config[section] ||= {}
          @config[section].merge! @config[:common]
        end

        # merge the config overrides hashes into config
        if cli_arguments.subcommand.config_overrides
          cli_arguments.subcommand.config_overrides.marshal_dump.each do |key, value|
            @config[key].merge! cli_arguments.subcommand.config_overrides.send(key)
          end
        end

        # merge the convenience arguments..
        config_sections.each do |section|
          if cli_arguments.subcommand.send(section.to_s)
            @config[section].merge! cli_arguments.subcommand.send(section.to_s).marshal_dump
          end
        end

        # merge the convenience argument parameters with config
        @config.deep_symbolize_keys!

      rescue => e
        puts "# failed to merge cli arguments with config"
        die e
      end
    end

    def load_file(cli_argument_config_file)

      if cli_argument_config_file
        config_file = cli_argument_config_file
      else
        config_file = File.join(File.basename(__FILE__), 'config.yaml')
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
      return @config[context][key] if @config[context][key]
      return @config[:common][key] if @config[:common][key]
      return nil
    end

    def [](key)
      @config[key]
    end

    # try and work out the hostname, presidence is:
    #
    # * config file
    # * user_data_template_variables cli args
    # 
    # note: raw user_data is not checked (not to be confused with user_data_template or user_data_template_variables..)
    #
    def establish_hostname_and_domain
      ShellSpinner "# checking whether hostname and domain have been set", false do

        hostname, domain = nil

        hostname = find_with_context(:hostname, :user_data_template_variables) unless find_with_context(:hostname, :user_data_template_variables).nil?
        domain   = find_with_context(:domain,   :user_data_template_variables) unless find_with_context(:domain,   :user_data_template_variables).nil?
        hostname = find_with_context(:hostname, :route53)                      unless find_with_context(:hostname, :route53).nil?
        domain   = find_with_context(:domain, :route53)                        unless find_with_context(:domain, :route53).nil?

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
          debug
        elsif domain and hostname.nil?
          debug "# WARNING: hostname not found"
          debug help
          debug
        elsif domain.nil? and hostname
          debug "# WARNING: domain not found"
          debug help
          debug
        else
          debug "# found hostname and domain:"
          debug "hostname: #{hostname}"
          debug "domain:   #{domain}"
          debug
        end
      end
    end


    def display
      puts "# config:"
      ap @config
      puts
    end
  end
end
