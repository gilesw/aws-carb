#!/usr/bin/env ruby

module AWSCarb
  class Config
    include Singleton

    attr_reader :config

    def create(cli_arguments)

      @config = load_file(cli_arguments.global.config_file)

      merge_cli_arguments_with_config(cli_arguments)

      establish_hostname_and_domain

      check_route53_settings
    end

    def check_route53_settings
      die 'route53: no zone id specified!' if @config[:route53][:zone].nil?
      die 'route53: no ttl specified!'     if @config[:route53][:zone].nil?
    end

    def merge_cli_arguments_with_config(cli_arguments)
      begin

        config_sections = [:common, :general, :ec2, :route53, :user_data_template_variables, :user_data_template]

        # special condition: common command line arguments are shared between all instances first..
        if cli_arguments.subcommand.config_overrides.common_variables
          @config[:common] ||= ActiveSupport::HashWithIndifferentAccess({})
          @config[:common].update cli_arguments.subcommand.config_overrides.common_variables
        end

        # all sections share 'common' variables..
        config_sections.each do |section|
          @config[section] ||= ActiveSupport::HashWithIndifferentAccess({})
          @config[section].update @config[:common]
        end

        # merge the config overrides hashes into config
        if cli_arguments.subcommand.config_overrides
          cli_arguments.subcommand.config_overrides.marshal_dump.each do |key, value|

            next if key == :common

            # key differs from command line argument - we lose the _variables suffix
            config_key = key.to_s.gsub('_variables', '').to_sym

            @config[config_key] ||= ActiveSupport::HashWithIndifferentAccess({})
            @config[config_key].update cli_arguments.subcommand.config_overrides.send(key)
          end
        end

        # merge the convenience arguments..
        config_sections.each do |section|
          if cli_arguments.subcommand.send(section.to_s)
            @config[section].update cli_arguments.subcommand.send(section.to_s).marshal_dump
          end
        end

      rescue => e
        puts "# failed to merge cli arguments with config"
        die e
      end
    end

    def load_file(cli_argument_config_file)

      # allow forcing of no config file..
      return if cli_argument_config_file.empty?

      config_file = cli_argument_config_file

      begin
        @config = ActiveSupport::HashWithIndifferentAccess.new(YAML.load_file(config_file))
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

        @config[:route53][:hostname] = find_with_context(:hostname, :user_data_template_variables) if find_with_context(:hostname, :user_data_template_variables)
        @config[:route53][:domain]   = find_with_context(:domain,   :user_data_template_variables) if find_with_context(:domain,   :user_data_template_variables)
        @config[:route53][:hostname] = find_with_context(:hostname, :route53)                      if find_with_context(:hostname, :route53)
        @config[:route53][:domain]   = find_with_context(:domain, :route53)                        if find_with_context(:domain, :route53)

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

        domain   = @config[:route53][:domain]
        hostname = @config[:route53][:hostname]

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

          @config[:route53][:new_dns_records] = {
            :public  => { :alias => "#{hostname}.#{domain}.",         :target => nil },
            :private => { :alias => "#{hostname}-private.#{domain}.", :target => nil }
          }
        end
      end

      puts
    end


    def display
      puts "# config:"
      ap @config
      puts
    end
  end
end
