#!/usr/bin/env ruby

def die(error)
  if $VERBOSE and error.respond_to?('backtrace')
    puts "# stack trace:"
    puts error.backtrace
    puts
  end

  puts "error: #{error}"

  exit 1
end

def debug(message = nil)
  puts message if $VERBOSE
end

