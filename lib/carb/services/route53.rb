#!/usr/bin/env ruby

module Carb
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
              die "error: record already exists: #{record[:alias]}" if record_sets[record[:alias], 'CNAME'].exists?
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

        ShellSpinner "# updating route53 with new CNAMES for host", false do

          @config[:route53][:new_dns_records][:public][:target]  = ec2.instance.public_dns_name
          @config[:route53][:new_dns_records][:private][:target] = ec2.instance.private_dns_name

          record_sets = @client.hosted_zones[@config[:route53][:zone]].resource_record_sets

          @config[:route53][:new_dns_records].each do |record_scope, record|
            new_record = record_sets[record[:alias], 'CNAME']

            raise "error: '#{record_scope}' record already exists: #{record[:alias]}" if new_record.exists?

            record_sets.create(record[:alias], 'CNAME', :ttl => @config[:route53][:ttl], :resource_records => [{:value => record[:target]}])
          end
        end

        puts
      end
    end
  end
end
