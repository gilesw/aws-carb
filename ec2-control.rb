#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), 'lib'))

require 'ec2-control'
require 'ec2-control/helpers'
require 'ec2-control/cli_argument_parser'
require 'ec2-control/config'
require 'ec2-control/user_data'
require 'ec2-control/aws/route53'
require 'ec2-control/aws/ec2'
require 'ec2-control/monkey_patches'

Ec2Control.run
