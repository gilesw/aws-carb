#!/usr/bin/env ruby

include Subcommands

# FIXME: this is all pretty messy
# * would probably be better to print the help for each command on the line below each argument

module Ec2Control
  module CliArgumentParser
    def self.parse
      cli_arguments                               = OpenStruct.new
      cli_arguments.global                        = OpenStruct.new
      cli_arguments.subcommand                    = OpenStruct.new
      cli_arguments.subcommand.config_overrides   = OpenStruct.new
      cli_arguments.subcommand.user_data_template = OpenStruct.new
      cli_arguments.subcommand.ec2                = OpenStruct.new
      cli_arguments.subcommand.route53            = OpenStruct.new

      # these are the only default we need to bother setting since they get used before we load the config file..
      cli_arguments.global.verbose = false
      cli_arguments.global.config_file = File.join(File.dirname(__FILE__), "config.yaml")

      global_options do |option|

        banner = <<-HEREDOC.strip_heredoc
        
                              amazon web services - ec2 control program

        usage:

            #{File.basename($0)} [global options] [subcommand [options]]\n"

        HEREDOC

        option.banner = banner

        option.summary_width = 50

        option.summary_indent = '    '

        option.separator "global options:"

        option.separator ""

        option.on("-c", "--config=FILE", "alternate config file") do |file|
          cli_arguments.global.config_file = file
        end

        option.separator ""

        option.on("-v", "--verbose", "enable debug messages") do |boolean|
          cli_arguments.global.verbose = boolean
          $VERBOSE = true
        end

        option.separator ""

        option.separator "    -h, --help                                         display help"
      end

      indent = ' ' * 55

      command :create do |option|
        banner = <<-HEREDOC.strip_heredoc
        
                              amazon web services - ec2 control program

        usage:

            #{File.basename($0)} create [options]

        HEREDOC

        option.banner      = banner
        option.description = "create an ec2 instance"

        option.summary_width  = 50
        option.summary_indent = '    '

        option.separator ""
        option.separator "    user_data template options:"
        option.separator ""

        option.on "--user-data-template=FILE", "user data template" do |user_data_template|
          cli_arguments.subcommand.user_data_template.user_data_template = user_data_template
        end

        option.separator ""

        option.on "--show-parsed-template=BOOLEAN", "display parsed template file" do |show_parsed_template|
          cli_arguments.subcommand.user_data_template.show_parsed_template = show_parsed_template
        end

        option.separator ""

        option.separator ""
        option.separator "    config file overrides:"
        option.separator ""

        option.on "--common-variables=HASH", String, "common variables" do |common_variables|
          begin
            data = eval(common_variables)
            raise unless data.class == Hash
            cli_arguments.subcommand.config_overrides.common_variables = data.deep_symbolize_keys
          rescue => e
            puts "# could not parse argument for --common-variables, is it a valid hash?"
            die e
          end
        end

        option.separator ""

        option.on "--general-variables=HASH", String, "general variables" do |general_variables|
          begin
            data = eval(general_variables)
            raise unless data.class == Hash
            cli_arguments.subcommand.config_overrides.general_variables = data.deep_symbolize_keys
          rescue => e
            puts "# could not parse argument for --general-variables, is it a valid hash?"
            die e
          end
        end

        option.separator ""

        option.on "--ec2-variables=HASH", String, "ec2 variables" do |ec2_variables|
          begin
            data = eval(ec2_variables)
            raise unless data.class == Hash
            cli_arguments.subcommand.config_overrides.ec2_variables = data.deep_symbolize_keys
          rescue => e
            puts "# could not parse argument for --ec2-variables, is it a valid hash?"
            die e
          end
        end

        option.separator ""

        option.on "--route53-variables=HASH", String, "route53 variables" do |route53_variables|
          begin
            data = eval(route53_variables)
            raise unless data.class == Hash
            cli_arguments.subcommand.config_overrides.route53_variables = data.deep_symbolize_keys
          rescue => e
            puts "# could not parse argument for --route53-variables, is it a valid hash?"
            die e
          end
        end

        option.separator ""

        option.on "--user-data-template-variables=HASH", String, "user data template variables" do |user_data_template_variables|
          begin
            data = eval(user_data_template_variables)
            raise unless data.class == Hash
            cli_arguments.subcommand.config_overrides.user_data_template_variables = data.deep_symbolize_keys
          rescue => e
            puts "# could not parse argument for --user-data-template-variables, is it a valid hash?"
            die e
          end
        end

        option.separator ""
        option.separator "          long descriptions for these parameters can be found here:\n            http://<TODO>"
        option.separator ""

        option.separator ""
        option.separator "    ec2 config convenience arguments:"
        option.separator ""

        option.on "--ec2-access-key-id=STRING", "access key id".downcase do |access_key_id|
          cli_arguments.subcommand.ec2.access_key_id = access_key_id
        end

        option.separator ""

        option.on "--ec2-secret-access-key=STRING", "secret access key".downcase do |secret_access_key|
          cli_arguments.subcommand.ec2.secret_access_key = secret_access_key
        end

        option.separator ""

        option.on "--image-id=STRING", "ID of the AMI you want to launch.".downcase do |image_id|
          cli_arguments.subcommand.ec2.image_id = image_id
        end

        option.separator ""

        option.on "--instance-type=STRING", "The type of instance to launch, for example \"m1.small\".".downcase do |instance_type|
          cli_arguments.subcommand.ec2.instance_type = instance_type
        end

        option.separator ""

        option.on "--key-name=STRING", "The name of the key pair to use.".downcase do |key_name|
          cli_arguments.subcommand.ec2.key_name = key_name
        end

        option.separator ""


        block_device_help = <<-HEREDOC.strip_heredoc
           :virtual_name - (String) Specifies the virtual device name.
           :device_name - (String) Specifies the device name (e.g., /dev/sdh).
           :ebs - (Hash) Specifies parameters used to automatically setup Amazon EBS volumes when the instance is launched.
             :snapshot_id - (String) The ID of the snapshot from which the volume will be created.
             :volume_size - (Integer) The size of the volume, in gigabytes.
             :delete_on_termination - (Boolean) Specifies whether the Amazon EBS volume is deleted on instance termination.
             :volume_type - (String) Valid values include:
               standard
               io1
           :iops - (Integer)
           :no_device - (String) Specifies the device name to suppress during instance launch.
        HEREDOC

        block_device_help = block_device_help.lines.map { |line| indent + "  #{line}" }

        block_device_help = "Specifies how block devices are exposed to the instance. Each mapping is made up of a virtualName and a deviceName.\n" + block_device_help.join.downcase

        option.on "--block-device-mappings=HASH", block_device_help do |key_name|
          cli_arguments.subcommand.ec2.key_name = key_name
        end

        option.separator ""

        option.on "--user-data=STRING", "Arbitrary user data. note: this is merged with user_data_template if also specified.".downcase do |user_data|
          cli_arguments.subcommand.ec2.user_data = user_data
        end

        option.separator ""

        option.on "--iam-instance-profile=STRING", "the name or ARN of an IAM instance profile.".downcase do |profile|
          cli_arguments.subcommand.ec2.iam_instance_profile = profile
        end

        option.separator ""

        option.on "--monitoring-enabled=BOOLEAN", "enable CloudWatch monitoring.".downcase do |boolean|
          cli_arguments.subcommand.ec2.monitoring_enabled = boolean
        end

        option.separator ""

        option.on "--availability-zone=STRING", "availability zone.".downcase do |zone|
          cli_arguments.subcommand.ec2.availability_zone = zone
        end

        option.separator ""

        option.on "--security-groups=ARRAY", Array, "Security groups. can be a single value or an array of values.\n#{indent}Values should be space deliminated group name strings.".downcase do |groups|
          cli_arguments.subcommand.ec2.security_groups = groups
        end

        option.separator ""

        option.on "--security-group-ids=ARRAY", Array, "security_group_ids accepts a single ID or an array of\n#{indent}security group IDs.".downcase do |group_ids|
          cli_arguments.subcommand.ec2.security_group_ids = group_ids
        end

        option.separator ""

        option.on "--disable-api-termination=BOOLEAN", "instance termination via the instance API.".downcase do |api_termination|
          cli_arguments.subcommand.ec2.disable_api_termination = api_termination
        end

        option.separator ""

        option.on "--instance-initiated-shutdown-behavior=STRING", "instance termination on instance-initiated shutdown".downcase do |shutdown_behavior|
          cli_arguments.subcommand.ec2.instance_initiated_shutdown_behavior = shutdown_behavior
        end

        option.separator ""

        option.on "--subnet=STRING", "The VPC Subnet (or subnet id string) to launch the instance in.".downcase do |subnet|
          cli_arguments.subcommand.ec2.subnet = subnet
        end

        option.separator ""

        option.on "--private_ip_address=STRING", "If you're using VPC, you can optionally use this option to assign the\n#{indent}instance a specific available IP address from the subnet (e.g., '10.0.0.25').\n#{indent}This option is not valid for instances launched outside a VPC (i.e.\n#{indent}those launched without the :subnet option).".downcase do |ip|
          cli_arguments.subcommand.ec2.private_ip_address = ip
        end

        option.separator ""

        option.on "--dedicated-tenancy=BOOLEAN", "Instances with dedicated tenancy will not share physical hardware with\n#{indent}instances outside their VPC. NOTE: Dedicated tenancy incurs an \n#{indent}additional service charge. This option is not valid for\n#{indent}instances launched outside a VPC (e.g.those launched without the :subnet option).".downcase do |tenancy|
          cli_arguments.subcommand.ec2.dedicated_tenancy = tenancy
        end

        option.separator ""

        option.on "--ebs-optimized=BOOLEAN", "EBS-Optimized instances enable Amazon EC2 instances to fully utilize the\n#{indent}IOPS provisioned on an EBS volume. EBS-optimized instances deliver dedicated\n#{indent}throughput between Amazon EC2 and Amazon EBS, with options between\n#{indent}500 Mbps and 1000 Mbps depending on the instance type used. When attached\n#{indent}to EBS-Optimized instances, Provisioned IOPS volumes are designed to\n#{indent}deliver within 10% of their provisioned performance 99.9% of the time.\n#{indent}NOTE: EBS Optimized instances incur an additional service charge.\n#{indent}This option is only valid for certain instance types.".downcase do |ebs_optimized|
          cli_arguments.subcommand.ec2.ebs_optimized = ebs_optimized
        end

        option.separator ""
        option.separator "        long descriptions for these parameters can be found here:\n          http://docs.aws.amazon.com/AWSRubySDK/latest/AWS/EC2/InstanceCollection.html"
        option.separator ""

        option.separator ""
        option.separator "    route53 convenience arguments:"
        option.separator ""

        option.on "--route53-access-key-id=STRING", "access key id".downcase do |access_key_id|
          cli_arguments.subcommand.route53.access_key_id = access_key_id
        end

        option.separator ""

        option.on "--route53-secret-access-key=STRING", "secret access key".downcase do |secret_access_key|
          cli_arguments.subcommand.route53.secret_access_key = secret_access_key
        end

        option.separator ""


        option.on "--zone=STRING", "route53 zone".downcase do |zone|
          cli_arguments.subcommand.route53.route = route
        end

        option.separator ""

        option.on "--ttl=STRING", "ttl".downcase do |ttl|
          cli_arguments.subcommand.route53.ttl = ttl
        end

        option.separator ""

      end

      begin
        #cli_arguments.chosen_subcommand = opt_parse
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

      return cli_arguments
    end
  end
end
