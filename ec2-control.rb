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

  #
  # main logic
  #

  def self.run

    #
    # cli argument parsing / config loading
    # 

    # debug (verbose) messages are not used until UserData point, and beyond

    # parse ARGV - we dont care about the subcommand at this point but we get
    # it for sake of completeness
    global_parameters, subcommand, subcommand_parameters = CliArgumentParser.parse

    # load YAML as config hash
    config = Config.load_file(global_parameters, subcommand_parameters)

    # for any variables not set using CLI args, load their settings from config file..
    # it's not possible to load defaults before parsing arguments because at that
    # point we dont know the path to the config file (if it varies from the app default)
    ec2_parameters = Config.load_defaults_from_config_file(config, subcommand_parameters)

    # check to see if user_data_template_variables is a valid hash..
    Config.check_parsing_of_user_data_template_variables(subcommand_parameters)

    Config.display(subcommand_parameters)

    ## check whether hostname and domain were specified by the user or are in the config file
    hostname, domain, new_records = establish_hostname_and_domain(config, subcommand_parameters)

    #
    # UserData handling
    # 

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

    ## initialize AWS object with credentials from config file
    initialize_aws_with_credentials(config)

    ## initialize ec2 object with credentials
    ec2 = initialize_ec2_instance(config, subcommand_parameters)


    ## check whether DNS records already exist..
    record_sets = check_hostname_and_domain_availability(config, hostname, domain, new_records)

    instance = create_instance(config, ec2, subcommand_parameters, user_data)

    update_route53(instance, config, hostname, domain, new_records, record_sets)

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

  module CliArgumentParser
    def self.parse
      global_parameters     = OpenStruct.new
      subcommand_parameters = OpenStruct.new

      # these are the only default we need to bother setting since they get used before we load the config file..
      global_parameters.verbose = false
      global_parameters.config_file = File.join(File.dirname(__FILE__), "config.yaml")

      global_options do |option|
        option.banner      = "\n\n                      amazon web services - ec2 control program"
        option.description = "\n\nusage:\n\n    #{File.basename($0)} [global options] [subcommand [options]]\n"

        option.summary_width = 50
        option.summary_indent = '    '

        option.separator "global options:"

        option.separator ""

        option.on("-c", "--config=FILE", "alternate config file") do |file|
          global_parameters.config_file = file
        end

        option.separator ""

        option.on("-v", "--verbose", "enable debug messages") do |boolean|
          global_parameters.debug = boolean
        end

        option.separator ""

        option.separator "    -h, --help                                         display help"
      end

      #add_help_option

      indent = ' ' * 55
      command :create do |option|
        option.banner      = "\n\n                      amazon web services - ec2 control program\n\nusage:\n\n    #{File.basename($0)} create [options]\n"
        option.description = "create an ec2 instance"

        option.summary_width = 50
        option.summary_indent = '    '

        # custom options to help out the user
        option.separator ""
        option.separator "    template options:"
        option.separator ""

        option.on "--user-data-template=FILE", "user data template" do |user_data_template|
          subcommand_parameters.user_data_template = user_data_template
        end

        option.separator ""

        option.on "--user-data-template-variables=HASH", String, "user data template variables" do |user_data_template_variables|
          subcommand_parameters.user_data_template_variables = user_data_template_variables
        end

        option.separator ""

        option.on "--show-parsed-template=BOOLEAN", "display parsed template file" do |show_parsed_template|
          subcommand_parameters.show_parsed_template = show_parsed_template
        end

        option.separator ""
        option.separator "          long descriptions for these parameters can be found here:\n            http://<TODO>"
        option.separator ""

        # ec2 specific options that are passed on to ec2 instance..

        option.separator ""
        option.separator "    ec2 options:"
        option.separator ""

        option.on "--region=STRING", "region to launch instance in, for example \"us-east-1\"" do |region|
          subcommand_parameters.region = region
        end

        option.separator ""

        option.on "--image-id=STRING", "ID of the AMI you want to launch.".downcase do |image_id|
          subcommand_parameters.image_id = image_id
        end

        option.separator ""

        option.on "--instance-type=STRING", "The type of instance to launch, for example \"m1.small\".".downcase do |instance_type|
          subcommand_parameters.instance_type = instance_type
        end

        option.separator ""

        option.on "--key-name=STRING", "The name of the key pair to use.".downcase do |key_name|
          subcommand_parameters.key_name = key_name
        end

        option.separator ""

        option.on "--user-data=STRING", "Arbitrary user data. note: this is merged with user_data_template if also specified.".downcase do |user_data|
          subcommand_parameters.user_data = user_data
        end

        option.separator ""

        option.on "--iam-instance-profile=STRING", "the name or ARN of an IAM instance profile.".downcase do |profile|
          subcommand_parameters.iam_instance_profile = profile
        end

        option.separator ""

        option.on "--monitoring-enabled=BOOLEAN", "enable CloudWatch monitoring.".downcase do |boolean|
          subcommand_parameters.monitoring_enabled = boolean
        end

        option.separator ""

        option.on "--availability-zone=STRING", "availability zone.".downcase do |zone|
          subcommand_parameters.availability_zone = zone
        end

        option.separator ""

        option.on "--security-groups=ARRAY", Array, "Security groups. can be a single value or an array of values.\n#{indent}Values should be space deliminated group name strings.".downcase do |groups|
          subcommand_parameters.security_groups = groups
        end

        option.separator ""

        option.on "--security-group-ids=ARRAY", Array, "security_group_ids accepts a single ID or an array of\n#{indent}security group IDs.".downcase do |group_ids|
          subcommand_parameters.security_group_ids = group_ids
        end

        option.separator ""

        option.on "--disable-api-termination=BOOLEAN", "instance termination via the instance API.".downcase do |api_termination|
          subcommand_parameters.disable_api_termination = api_termination
        end

        option.separator ""

        option.on "--instance-initiated-shutdown-behavior=STRING", "instance termination on instance-initiated shutdown".downcase do |shutdown_behavior|
          subcommand_parameters.instance_initiated_shutdown_behavior = shutdown_behavior
        end

        option.separator ""

        option.on "--subnet=STRING", "The VPC Subnet (or subnet id string) to launch the instance in.".downcase do |subnet|
          subcommand_parameters.subnet = subnet
        end

        option.separator ""

        option.on "--private_ip_address=STRING", "If you're using VPC, you can optionally use this option to assign the\n#{indent}instance a specific available IP address from the subnet (e.g., '10.0.0.25').\n#{indent}This option is not valid for instances launched outside a VPC (i.e.\n#{indent}those launched without the :subnet option).".downcase do |ip|
          subcommand_parameters.private_ip_address = ip
        end

        option.separator ""

        option.on "--dedicated-tenancy=BOOLEAN", "Instances with dedicated tenancy will not share physical hardware with\n#{indent}instances outside their VPC. NOTE: Dedicated tenancy incurs an \n#{indent}additional service charge. This option is not valid for\n#{indent}instances launched outside a VPC (e.g.those launched without the :subnet option).".downcase do |tenancy|
          subcommand_parameters.dedicated_tenancy = tenancy
        end

        option.separator ""

        option.on "--ebs-optimized=BOOLEAN", "EBS-Optimized instances enable Amazon EC2 instances to fully utilize the\n#{indent}IOPS provisioned on an EBS volume. EBS-optimized instances deliver dedicated\n#{indent}throughput between Amazon EC2 and Amazon EBS, with options between\n#{indent}500 Mbps and 1000 Mbps depending on the instance type used. When attached\n#{indent}to EBS-Optimized instances, Provisioned IOPS volumes are designed to\n#{indent}deliver within 10% of their provisioned performance 99.9% of the time.\n#{indent}NOTE: EBS Optimized instances incur an additional service charge.\n#{indent}This option is only valid for certain instance types.".downcase do |ebs_optimized|
          subcommand_parameters.ebs_optimized = ebs_optimized
        end

        option.separator ""
        option.separator "        long descriptions for these parameters can be found here:\n          http://docs.aws.amazon.com/AWSRubySDK/latest/AWS/EC2/InstanceCollection.html"
        option.separator ""
      end

      begin
        subcommand = opt_parse

        # show help if no arguments passed in
        if subcommand.nil?
          add_subcommand_help
          puts @global

          exit 1
        end

        if ARGV.length > 0
          raise ArgumentError, "unknown command line argument(s): #{ARGV.inspect.to_s}"
        end
      rescue => e
        puts e
        exit 1
      end

      return global_parameters, subcommand, subcommand_parameters
    end
  end

  module Config
    def self.load_file(global_parameters)
      begin
        config = YAML.load_file(global_parameters.config_file)
      rescue => e
        puts "# failed to load config file: '#{global_parameters.config_file}'"
        die e
      end

      return config
    end

    def self.check_parsing_of_user_data_template_variables(subcommand_parameters)

      return unless subcommand_parameters.user_data_template_variables

      begin
        config = eval(subcommand_parameters.user_data_template_variables)

        raise ArguementError, "could not parse user_data_template_variables: '#{config}'" unless config.class == Hash
      rescue => e
        puts "# failed to parse user_data_template_variables, is your string properly quoted?"
        die e
      end

      return config
    end

    def self.load_defaults_from_config_file(config, subcommand_parameters)

      # NOTE: not all 'subcommand parameters' are ec2 parameters - a few of them are used elsewhere.

      # presedence of config values is as follows:
      # 
      # application default < config file < command line argument
      #
      # unfortunately we start off with a struct full of command line argument values since the config
      # file location isnt finalised until after the cli args have been parsed.

      # some sensible defaults..
      subcommand_parameters.region                               = "us-east-1"
      subcommand_parameters.show_parsed_template                 = false
      subcommand_parameters.image_id                             = "ami-a73264ce" # 64bit ubuntu precise
      subcommand_parameters.instance_type                        = "t1.micro"

      general_parameters = [ :region, :user_data_template, :user_data_template_variables, :show_parsed_template ]

      general_parameters.each do |parameter|
        subcommand_parameters.method(parameter) = config['general'][parameter.to_s] if config['general']
      end

      ec2_available_parameters = [
        :image_id, :instance_type, :key_name, :user_data, :iam_instance_profile,
        :availability_zone, :security_group_ids, :subnet, :private_ip_address,
        :dedicated_tenancy, :disable_api_termination, :instance_initiated_shutdown_behavior,
        :ebs_optimized, :monitoring_enabled
      ]

      ec2_available_parameters.each do |parameter|
        subcommand_parameters.method(parameter) = config['ec2'][parameter.to_s] if config['ec2']
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

  module UserData
    def self.resolve_template(erb, user_data_template_variables_merged)
      begin
        return erb.result(user_data_template_variables_merged)
      rescue => e
        puts "# failed to resolve variables in user_data_template:"
        die e
      end
    end

    def self.show_parsed_template(subcommand_parameters, user_data_template_resolved)

      return unless subcommand_parameters.show_parsed_template

      puts "# --- beginning of parsed user_data_template ---"
      puts
      begin
        puts user_data_template_resolved
      rescue => e
        puts "error: could not display parsed template!"
        puts e
      end
      puts
      puts "# --- end of parsed user_data_template ---"
      puts
    end

    def self.combine_user_data(subcommand_parameters, user_data_template_resolved)

      # if user_data_template and user_data are supplied then combine them, otherwise just
      # use user_data (which is empty by default)
      begin
        if ! user_data_template_resolved.nil? and ! subcommand_parameters.user_data.nil?
          puts "# combining user_data with user_data_template"
          user_data = user_data_template_resolved + subcommand_parameters.user_data
          puts
        elsif ! user_data_template_resolved.nil? and subcommand_parameters.user_data.nil?
          debug "# no raw user_data parsed in"
          user_data = user_data_template_resolved
          debug
        elsif user_data.nil?
          debug "# no user_data specified on the command line"
          user_data = ""
          debug
        else
          puts "# using user_data from cli argument"
          user_data = subcommand_parameters.user_data
          puts
        end

      rescue => e
        puts "# failed to combine user_data!"
        die e
      end

      return user_data
    end
  end

  module AWS
    module Ec2
      def self.initialize_ec2_instance(config, subcommand_parameters)

        ec2 = nil

        ShellSpinner "# initializing ec2 session", false do
          begin
            AWS.config(config['ec2'])
            ec2 = AWS::EC2.new.regions[subcommand_parameters.region]
            puts
          rescue => e
            puts "error: failed to create ec2 session, check that you're using a valid region!"
            die e
          end
        end

        return ec2
      end

      def self.create_instance(config, ec2, subcommand_parameters, user_data)

        instance = nil

        ShellSpinner "# creating instance", false do
          begin
            instance = ec2.instances.create(ec2_parameters)
          rescue => e
            die e
          end
        end

        puts

        ShellSpinner "# awaiting build completion", false do
          sleep 1 until instance.status != :pending
        end

        puts

        ShellSpinner "# awaiting running state", false do
          sleep 1 until instance.status == :running
        end

        puts

        return instance
      end
    end

    module Route53
      def self.initialize_aws_with_credentials(config)
        begin
          aws = AWS.config(config['ec2'])
        rescue => e
          puts <<-HEREDOC.strip_heredoc
            # failed to load aws credentials!
            # is there an 'ec2' section in your config file
            # that contains 'access_key_id' and 'secret_access_key'
            # entries?
          HEREDOC

          die e
        end

        return aws
      end

      def self.check_hostname_and_domain_availability(config, hostname, domain, new_records)

        return unless hostname and domain

        die 'no route53 configuration in zone file!'   if config['route53'].nil?
        die 'route53: no zone id specified in config!' if config['route53']['zone'].nil?
        die 'route53: no ttl specified in config!'     if config['route53']['zone'].nil?

        ShellSpinner "# checking to see if hostname is in use", false do
          begin
            record_sets = AWS::Route53::HostedZone.new(config['route53']['zone']).resource_record_sets

            new_records.each_value do |record|
              die "error: record already exists: #{record[:alias]}" if record_sets[record[:alias], 'CNAME'].exists?
            end

            puts
          rescue => e
            puts "# could not check to see if DNS records exist:"
            die e
          end
        end
      end

      def self.update_route53(instance, config, hostname, domain, new_records, record_sets)

        return if hostname.nil? or domain.nil?

        ShellSpinner "# updating route53 with new CNAME for host", false do

          new_records[:public][:target]  = instance.public_dns_name
          new_records[:private][:target] = instance.private_dns_name

          record_sets = AWS::Route53::HostedZone.new(config['route53']['zone']).resource_record_sets

          new_records.each do |record_scope, record|
            new_record = record_sets[record[:alias], 'CNAME']

            raise "error: '#{record_scope}' record already exists: #{record[:alias]}" if new_record.exists?

            record_sets.create(record[:alias], 'CNAME', :ttl => config['route53']['ttl'], :resource_records => [{:value => record[:target]}])
          end
        end
      end
    end
  end
end

# monkeypatch shell spinner to fix some bugs..

module ShellSpinner
  class Runner
    def wrap_block(text = nil, colorize = true, &block)
      with_message(text) { with_spinner(&block) }
    end

    private

    # FIXME: better way to disable colours?
    #colorize = colorize ? lambda { |s,c| s.colorize(c) } : lambda { |s,c| s }
    #colorize.call(s, :red)

    def with_message(text = nil, colorize = false)
      if !colorize or $stdout.tty?
        String.class_eval do
          def colorize(color)
            self
          end
        end
      end

      begin
        print "#{text}... " unless text.nil?

        catch_user_output { yield }

        print "done\n".colorize(:green) unless text.nil?

        print user_output.colorize(:blue)

      rescue Exception => e
        print "\bfail\n".colorize(:red) unless text.nil?

        print user_output.colorize(:blue)

        re_raise_exception e
      end
    end
  end
end

def ShellSpinner(text = nil, colorize = true, &block)
  runner = ShellSpinner::Runner.new

  runner.wrap_block(text, colorize, &block)
end

# override the output from optparse to be a bit more aesthetically pleasing
module Subcommands
  def print_actions
    cmdtext = "subcommands:\n"

    @commands.each_pair do |c, opt|
      cmdtext << "\n   #{c}                                              #{opt.call.description}"
    end

    unless @aliases.empty?
      cmdtext << "\n\naliases: \n"
      @aliases.each_pair { |name, val| cmdtext << "   #{name} - #{val}\n"  }
    end

    cmdtext << "\n\n   help <command>                                      for more information on a specific command\n\n"
  end

  def command *names
    name = names.shift

    @commands ||= {}
    @aliases  ||= {}

    names.each { |n| @aliases[n.to_s] = name.to_s } if names.length > 0

    opt = lambda do
      OptionParser.new do |opts|
        yield opts
        opts.banner << "\noptions:"
      end
    end

    @commands[name.to_s] = opt
  end
end

# helpers

def die(message)
  puts "error: #{message}"
  exit 1
end

def debug(message = nil)
  puts message if $VERBOSE == true
end

# go!

Ec2Control.run
