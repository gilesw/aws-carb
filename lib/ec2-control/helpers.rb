#!/usr/bin/env ruby

def die(message)
  puts "error: #{message}"
  exit 1
end

def debug(message = nil)
  puts message if $VERBOSE == true
end

