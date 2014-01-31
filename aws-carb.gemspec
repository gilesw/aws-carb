# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'aws-carb/version'

Gem::Specification.new do |spec|
  spec.name          = "aws-carb"
  spec.version       = AWSCarb::VERSION
  spec.authors       = ["Rob Wilson"]
  spec.email         = ["roobert@gmail.com"]
  spec.summary       = "aws - cloudinit and route53 bootstrap"
  spec.description   = "a tool for provisioning ec2 instances with a templated cloudinit configuration, with the optional ability to update route53 with dns records to point at your new instance"
  spec.homepage      = "http://github.com/roobert/aws-carb"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake",    "~> 10.0.0"

  spec.add_dependency "activesupport", ">= 4.0.0"
  spec.add_dependency "andand",        ">= 1.3.0"
  spec.add_dependency "awesome_print", ">= 1.2.0"
  spec.add_dependency "aws-sdk",       ">= 1.33.0"
  spec.add_dependency "colorize",      ">= 0.6.0"
  spec.add_dependency "erubis",        ">= 2.7.0"
  spec.add_dependency "shell-spinner", ">= 1.0.0"
  spec.add_dependency "subcommand",    ">= 1.0.0"
end
