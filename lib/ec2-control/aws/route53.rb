#!/usr/bin/env ruby

module Ec2Control
  module AWS
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

      def self.check_hostname_and_domain_availability(config)

        # FIXME - horrible and also should this go in Config?
        hostname = config.find_with_context(:hostname, :user_data_template_variables) if config.find_with_context(:hostname, :user_data_template_variables)
        domain = config.find_with_context(:domain, :user_data_template_variables) if config.find_with_context(:domain, :user_data_template_variables)
        hostname = config.find_with_context(:hostname, :route53) if config.find_with_context(:hostname, :route53)
        domain = config.find_with_context(:domain, :route53) if config.find_with_context(:hostname, :route53)

        return unless hostname and domain

        # FIXME - should this go in Config?
        config[:route53][:new_dns_records] = {
          :public  => { :alias => "#{hostname}.#{domain}.",         :target => nil },
          :private => { :alias => "#{hostname}-private.#{domain}.", :target => nil }
        }


        die 'no route53 configuration in zone file!'   if config[:route53].nil?
        die 'route53: no zone id specified in config!' if config[:route53][:zone].nil?
        die 'route53: no ttl specified in config!'     if config[:route53][:zone].nil?

        ShellSpinner "# checking to see if hostname is in use", false do
          begin
            record_sets = ::AWS::Route53::HostedZone.new(config[:route53][:zone]).resource_record_sets

            config[:route53][:new_dns_records].each_value do |record|
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

          record_sets = ::AWS::Route53::HostedZone.new(config[:route53][:zone]).resource_record_sets

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
