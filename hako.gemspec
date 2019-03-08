# frozen_string_literal: true
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'hako/version'

Gem::Specification.new do |spec|
  spec.name          = 'hako'
  spec.version       = Hako::VERSION
  spec.authors       = ['Kohei Suzuki']
  spec.email         = ['eagletmt@gmail.com']

  spec.summary       = 'Deploy Docker container'
  spec.description   = 'Deploy Docker container'
  spec.homepage      = 'https://github.com/eagletmt/hako'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 2.3.0'

  spec.add_dependency 'aws-sdk-applicationautoscaling', '~> 1'
  spec.add_dependency 'aws-sdk-autoscaling', '~> 1'
  spec.add_dependency 'aws-sdk-cloudwatch', '~> 1'
  spec.add_dependency 'aws-sdk-cloudwatchlogs', '~> 1'
  spec.add_dependency 'aws-sdk-ec2', '~> 1'
  spec.add_dependency 'aws-sdk-ecs', '~> 1'
  spec.add_dependency 'aws-sdk-elasticloadbalancing', '~> 1'
  spec.add_dependency 'aws-sdk-elasticloadbalancingv2', '~> 1'
  spec.add_dependency 'aws-sdk-s3', '~> 1'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rubocop', '>= 0.36.0'
  spec.add_development_dependency 'yard'
end
