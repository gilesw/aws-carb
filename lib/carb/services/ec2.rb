#!/usr/bin/env ruby

module Carb
  module Services
    class Ec2

      include Singleton

      attr_reader :instance

      def client(config)
        @config = config
        @instance = nil

        ShellSpinner "# configuring ec2 session", false do
          begin
            @client = AWS::EC2.new(config[:ec2])
            @client.regions[@config.find_with_context(:region, :ec2)]
            puts
          rescue => e
            puts "error: failed to create ec2 session, check that you're using a valid region!"
            die e
          end
        end
      end

      def create_instance

        instance = nil

        ShellSpinner "# creating instance", false do

          # FIXME: this is naff

          begin
            allowed_ec2_parameters = [
              :count,
              :iam_instance_profile,
              :block_device_mappings,
              :virtual_name,
              :device_name,
              :ebs,
              :snapshot_id,
              :volume_size,
              :delete_on_termination,
              :volume_type,
              :iops,
              :no_device,
              :monitoring_enabled,
              :availability_zone,
              :image_id,
              :key_name,
              :key_pair,
              :security_groups,
              :security_group_ids,
              :user_data,
              :instance_type,
              :kernel_id,
              :ramdisk_id,
              :disable_api_termination,
              :instance_initiated_shutdown_behavior,
              :subnet,
              :private_ip_address,
              :dedicated_tenancy,
              :ebs_optimized,
            ]

            ec2_config = {}

            allowed_ec2_parameters.each do |param|
              ec2_config[param] = @config[:ec2][param] if @config[:ec2][param]
            end

            @instance = @client.instances.create(ec2_config)
          rescue => e
            puts "# failed to create new ec2 instance:"
            die e
          end
        end

        puts

        ShellSpinner "# awaiting build completion", false do
          sleep 1 until @instance.status != :pending
        end

        puts

        ShellSpinner "# awaiting running state", false do
          sleep 1 until @instance.status == :running
        end

        puts
      end
    end
  end
end
