#!/usr/bin/env ruby
module Ec2Control
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
end
