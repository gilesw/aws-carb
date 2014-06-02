#!/usr/bin/env ruby

module AWSCarb
  # named so as not to clash with AWS module from aws-sdk
  module Services
    class Route53

      include Singleton

      def client(config)
        @config = config

        begin
          ShellSpinner "# configuring route53 session", false do
            @client = ::AWS::Route53.new(@config[:route53])
          end

          puts
        rescue => e
          puts "error: failed to create route53 session"
          die e
        end
      end

      def check_hostname_and_domain_availability

        ShellSpinner "# checking to see if hostname and domain have been configured", false do

          if @config[:route53].andand[:new_dns_records]

          else
            debug "# skipping route53 check since either hostname or domain wasn't found:"
            debug "hostname not found" if hostname.nil?
            debug "domain not found"   if domain.nil?
            debug
          end
        end

        puts

        return unless @config[:route53].andand[:new_dns_records]

        ShellSpinner "# checking to see if record exists", false do
          begin
            record_sets = @client.hosted_zones[@config[:route53][:zone]].resource_record_sets

            @config[:route53][:new_dns_records].each_value do |record|
              die "error: record already exists: #{record[:alias]}" if record_sets[record[:alias], 'A'].exists?
            end
          rescue => e
            puts "# could not check to see if DNS records exist:"
            die e
          end
        end

        puts
      end

      def create_records(ec2)
        if @config[:route53][:new_dns_records].nil?
          debug "# skipping creation of new records on route53"
          debug
          return
        end

        ShellSpinner "# updating route53 with new A records for host", false do

          @config[:route53][:new_dns_records][:public][:target]  = ec2.instance.ip_address
          @config[:route53][:new_dns_records][:private][:target] = ec2.instance.private_ip_address

          record_sets = @client.hosted_zones[@config[:route53][:zone]].resource_record_sets

          @config[:route53][:new_dns_records].each do |record_scope, record|
            new_record = record_sets[record[:alias], 'A']

            raise "error: '#{record_scope}' record already exists: #{record[:alias]}" if new_record.exists?

            # this could be blank if we're adding to a vpc and the instance has no external IP
            next if record[:target].nil?

            new_record = {
              :name    => record[:alias],
              :type    => 'A',
              :options => {
                :ttl              => @config[:route53][:ttl],
                :resource_records => [{ :value => record[:target] }]
              }
            }

            record_sets.create(new_record[:name], new_record[:type], new_record[:options])
          end
        end

        puts
      end
    end
  end
end
