#!/usr/bin/env ruby

module Ec2Control
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
end
