#!/usr/bin/env ruby

module Ec2Control
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
  end
end
