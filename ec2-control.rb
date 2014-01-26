#!/usr/bin/env ruby

require 'aws-sdk'
require 'yaml'
require 'erubis'
require 'awesome_print'
require 'securerandom'
require 'shell-spinner'
require 'active_support'
require 'ostruct'
require 'subcommand'

include Subcommands

# * change 'puts' to debug
# * add security group and vpc params
# * usage banner
# * route 53
# * list stuff
# * terminate stuff

# monkeypatch shell spinner to fix some bugs..
module ShellSpinner
  class Runner
    def wrap_block(text = nil, colorize = true, &block)
      with_message(text) { with_spinner &block }
    end

    private

    def with_message(text = nil, colorize = false)
      if colorize
        require 'colorize'
      else
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
    cmdtext = "subcommands:"

    @commands.each_pair do |c, opt|
      cmdtext << "\n   #{c}                            #{opt.call.description}"
    end

    unless @aliases.empty?
      cmdtext << "\n\naliases: \n"
      @aliases.each_pair { |name, val| cmdtext << "   #{name} - #{val}\n"  }
    end

    cmdtext << "\n\nsee '#{$0} help <command>' for more information on a specific command\n\n"
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

def die(message)
  puts "error: #{message}"
  exit 1
end

def debug(message = nil)
  puts message if $verbose == true
end

module Ec2Control
  module CliArgumentParser
    def self.parse
      global_parameters     = OpenStruct.new
      subcommand_parameters = OpenStruct.new

      global_parameters.config_file = File.join(File.dirname(__FILE__), "config.yaml")

      global_parameters.verbose = false

      subcommand_parameters.region                       = "us-east-1"
      subcommand_parameters.image_id                     = "ami-a73264ce"
      subcommand_parameters.instance_type                = "t1.micro"
      subcommand_parameters.key_name                     = "aws-semantico"
      subcommand_parameters.user_data                    = nil
      subcommand_parameters.user_data_template           = nil
      subcommand_parameters.user_data_template_variables = nil
      subcommand_parameters.show_parsed_template         = false

      global_options do |option|
        option.banner      = "\n             amazon web services - ec2 control program"
        option.description = "\nusage:\n    #{File.basename($0)} [global options] [subcommand [options]]\n"

        option.separator "global options:"

        option.on("-c", "--config=FILE", "alternate config file") do |file|
          global_parameters.config_file = file
        end

        option.on("-v", "--verbose", "enable debug messages") do |boolean|
          global_parameters.debug = boolean
        end
      end

      add_help_option

      command :create do |option|
        option.banner      = "\n             amazon web services - ec2 control program\n\nusage:\n    #{File.basename($0)} create [options]\n"
        option.description = "create an ec2 instance"

        option.summary_width = 50
        option.summary_indent = '    '

        option.on "--region=REGION", "specify a region" do |region|
          subcommand_parameters.region = region
        end

        option.on "--image-id=ID", "AMI image ID" do |image_id|
          subcommand_parameters.image_id = image_id
        end

        option.on "--instance-type=TYPE", "instance type" do |instance_type|
          subcommand_parameters.instance_type = instance_type
        end

        option.on "--key-name=NAME", "key_name" do |key_name|
          subcommand_parameters.key_name = key_name
        end

        option.on "--user-data=DATA", "user data" do |user_data|
          subcommand_parameters.user_data = user_data
        end

        option.on "--user-data-template=FILE", "user data template" do |user_data_template|
          subcommand_parameters.user_data_template = user_data_template
        end

        option.on "--user-data-template-variables=HASH", String, "user data template variables" do |user_data_template_variables|
          subcommand_parameters.user_data_template_variables = user_data_template_variables
        end

        option.on "--show-parsed-template=BOOLEAN", "display parsed template file" do |show_parsed_template|
          subcommand_parameters.show_parsed_template = show_parsed_template
        end
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

      return subcommand, global_parameters, subcommand_parameters
    end
  end

  module Config
    def self.check(global_parameters, subcommand_parameters)
      begin
        config = YAML.load_file(global_parameters.config_file)
      rescue => e
        puts "# failed to load config file: '#{global_parameters.config_file}'"
        die e
      end

      begin
        eval(subcommand_parameters.user_data_template_variables) if subcommand_parameters.user_data_template_variables
      rescue => e
        puts "# failed to parse user_data_template_variables, is your string properly quoted?"
        die e
      end

      return config
    end

    def self.display(subcommand_parameters)
      puts "# EC2 instance options:"

      # FIXME: align variables in a column..
      keys        = subcommand_parameters.marshal_dump.group_by(&:size).max
      longest_key = keys[1][keys[0]][0].length

      subcommand_parameters.marshal_dump.each do |key, value|
        puts "#{key}:".to_s.ljust(longest_key + 2) + "#{value}" unless value.nil?
      end

      puts
    end
  end

  module UserData
    def self.configure_user_data(config, subcommand_parameters)

      erb, merged_user_data_template_variables = merge_variables_for_user_data_template(config, subcommand_parameters)

      if subcommand_parameters.user_data_template_variables
        user_data_template_resolved = resolve_template(erb, merged_user_data_template_variables)
      end

      show_parsed_template(subcommand_parameters, user_data_template_resolved)

      user_data = combine_user_data(subcommand_parameters, user_data_template_resolved)

      return user_data
    end

    private

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

  #
  # main logic
  #

  attr_reader :verbose

  def self.run

    subcommand, global_parameters, subcommand_parameters, config = CliArgumentParser.parse

    $verbose = global_parameters.verbose

    config = Config.check(global_parameters, subcommand_parameters)
    Config.display(subcommand_parameters)

    ## establish what user_data will be passed into the cloud instance
    user_data = UserData.configure_user_data(config, subcommand_parameters)

    ## initialize AWS object with credentials from config file
    initialize_aws_with_credentials(config)

    ## initialize ec2 object with credentials
    ec2 = initialize_ec2_instance(config, subcommand_parameters)

    ## check whether hostname and domain were specified by the user or are in the config file
    hostname, domain, new_records = establish_hostname_and_domain(config, subcommand_parameters)

    ## check whether DNS records already exist..
    record_sets = check_hostname_and_domain_availability(config, hostname, domain, new_records)

    instance = create_instance(config, ec2, subcommand_parameters, user_data)

    update_route53(instance, config, hostname, domain, new_records, record_sets)

    show_instance_details(instance, new_records, hostname, domain)
  end

  private

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

  def self.initialize_aws_with_credentials(config)
    begin
      aws = AWS.config(config['ec2'])
    rescue => e
      puts "# failed to load aws credentials!"
      puts "# is there an 'ec2' section in your config file"
      puts "# that contains 'access_key_id' and 'secret_access_key'"
      puts "# entries?"
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

  def self.create_instance(config, ec2, subcommand_parameters, user_data)

    instance = nil

    ShellSpinner "# creating instance", false do
      begin
        instance = ec2.instances.create(
          :image_id      => subcommand_parameters.image_id,
          :instance_type => subcommand_parameters.instance_type,
          :key_name      => subcommand_parameters.key_name,
          :user_data     => user_data,
        )
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

  def self.show_instance_details(instance, new_records, hostname, domain)
    puts "# instance details:"
    puts "id:               #{instance.id}"
    puts "public ip:        #{instance.public_ip_address}"
    puts "public aws fqdn:  #{instance.public_dns_name}"
    puts "private ip:       #{instance.private_ip_address}"
    puts "private aws fqdn: #{instance.private_dns_name}"

    unless hostname.nil? or domain.nil?
      puts "public fqdn:      #{new_records[:public][:alias]}"
      puts "private fqdn:     #{new_records[:private][:alias]}"
    end

    puts

    puts "# connect: "
    puts "ssh #{instance.dns_name} -l ubuntu"
  end
end

Ec2Control.run
