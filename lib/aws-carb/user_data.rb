#!/usr/bin/env ruby

module AWSCarb
  class UserData

    include Singleton

    attr_accessor :combined_user_data

    def create(config)
      user_data_template_resolved = resolve_template(config)
      @combined_user_data         = combine_user_data(config, user_data_template_resolved)
      return @combined_user_data
    end

    def resolve_template(config)

      user_data_template         = nil
      resolved_template          = nil

      # FIXME: blank templates / empty templates / no template should work..

      return nil unless config[:ec2] and config[:user_data_template][:file]

      ShellSpinner "# loading template", false do
        begin
          template_file = config[:user_data_template][:file]

          raise ArgumentError, "no such file: #{template_file}" unless File.exist?(template_file)

          user_data_template = File.read(template_file)
        rescue => e
          puts "# unable to open template file:"
          die e
        end
      end

      puts

     ShellSpinner "# parsing template"  do
        begin
          resolved_template = Erubis::Eruby.new(user_data_template).result(config[:user_data_template_variables])
        rescue => e
          puts "# failed to resolve variables in user_data_template:"
          die e
        end
      end

      puts

      return resolved_template
    end

    def combine_user_data(config, user_data_template_resolved)

      # if user_data_template and user_data are supplied then combine them, otherwise just
      # use user_data (which is empty by default)
      begin
        if config[:ec2].andand[:user_data]
          user_data = config[:ec2][:user_data]
        end

        if ! user_data_template_resolved.nil? and ! user_data.nil?
          puts "# combining user_data with user_data_template"
          user_data = user_data_template_resolved + user_data
          puts
        elsif ! user_data_template_resolved.nil? and user_data.nil?
          debug "# no raw user_data parsed in"
          user_data = user_data_template_resolved
          debug
        elsif user_data.nil?
          debug "# no user_data or user_data_template specified on the command line"
          user_data = ""
          debug
        else
          debug "# using user_data from cli argument"
          debug
        end

      rescue => e
        puts "# failed to combine user_data!"
        die e
      end

      return user_data
    end

    def display
      return if @combined_user_data.nil?

      puts "# --- beginning of user_data ---"
      puts
      begin
        puts @combined_user_data
      rescue => e
        puts "error: could not display user_data!"
        puts e
      end
      puts
      puts "# --- end of user_data ---"
      puts
    end
  end
end
