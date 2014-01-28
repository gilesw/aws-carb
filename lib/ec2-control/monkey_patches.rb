#!/usr/bin/env ruby

# monkeypatch shell spinner to fix some bugs..

module ShellSpinner
  class Runner
    def wrap_block(text = nil, colorize = true, &block)
      with_message(text) { with_spinner(&block) }
    end

    private

    # FIXME: better way to disable colours?
    #colorize = colorize ? lambda { |s,c| s.colorize(c) } : lambda { |s,c| s }
    #colorize.call(s, :red)

    def with_message(text = nil, colorize = false)
      if !colorize or $stdout.tty?
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
    cmdtext = "subcommands:\n"

    @commands.each_pair do |c, opt|
      cmdtext << "\n   #{c}                                              #{opt.call.description}"
    end

    unless @aliases.empty?
      cmdtext << "\n\naliases: \n"
      @aliases.each_pair { |name, val| cmdtext << "   #{name} - #{val}\n"  }
    end

    cmdtext << "\n\n   help <command>                                      for more information on a specific command\n\n"
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

# helpers

def die(message)
  puts "error: #{message}"
  exit 1
end

def debug(message = nil)
  puts message if $VERBOSE == true
end
