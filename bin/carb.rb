#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), 'lib'))

require 'carb'
require 'carb/helpers'
require 'carb/cli_argument_parser'
require 'carb/config'
require 'carb/user_data'
require 'carb/services/route53'
require 'carb/services/ec2'
require 'carb/monkey_patches'

Carb.run
