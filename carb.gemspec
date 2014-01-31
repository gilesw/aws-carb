# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'carb/version'

Gem::Specification.new do |spec|
  spec.name          = "carb"
  spec.version       = Carb::VERSION
  spec.authors       = ["Rob Wilson"]
  spec.email         = ["roobert@gmail.com"]
  spec.summary       = "aws - cloudinit and route53 bootstrap"
  spec.description   = "a tool for provisioning ec2 instances with a templated cloudinit configuration, with the optional ability to update route53 with dns records to point at your new instance"
  spec.homepage      = "http://github.com/roobert/carb"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"

  spec.add_dependency "aws-sdk"
  spec.add_dependency "erubis"
  spec.add_dependency "awesome_print"
  spec.add_dependency "shell-spinner"
  spec.add_dependency "activesupport"
  spec.add_dependency "subcommand"
  spec.add_dependency "andand"
  spec.add_dependency "colorize"
  spec.add_dependency "aws-sdk"
  spec.add_dependency "erubis"
  spec.add_dependency "awesome_print"
  spec.add_dependency "shell-spinner"
  spec.add_dependency "activesupport"
  spec.add_dependency "subcommand"
  spec.add_dependency "andand"
  spec.add_dependency "colorize"
end
