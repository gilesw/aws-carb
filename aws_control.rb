#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), 'lib'))

require 'aws_control'
require 'aws_control/helpers'
require 'aws_control/cli_argument_parser'
require 'aws_control/config'
require 'aws_control/user_data'
require 'aws_control/services/route53'
require 'aws_control/services/ec2'
require 'aws_control/monkey_patches'

AWSControl.run
