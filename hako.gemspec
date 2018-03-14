# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
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
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 2.3.0'

  spec.add_dependency 'aws-sdk-applicationautoscaling'
  spec.add_dependency 'aws-sdk-autoscaling'
  spec.add_dependency 'aws-sdk-cloudwatch'
  spec.add_dependency 'aws-sdk-cloudwatchlogs'
  spec.add_dependency 'aws-sdk-ec2'
  spec.add_dependency 'aws-sdk-ecs', '>= 1.4.0'
  spec.add_dependency 'aws-sdk-elasticloadbalancing'
  spec.add_dependency 'aws-sdk-elasticloadbalancingv2'
  spec.add_dependency 'aws-sdk-s3'
  spec.add_dependency 'aws-sdk-sns'
  spec.add_dependency 'jsonnet'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'coveralls'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rubocop', '>= 0.53.0'
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'yard'
end
