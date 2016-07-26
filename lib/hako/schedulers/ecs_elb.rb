# frozen_string_literal: true
require 'aws-sdk'
require 'hako'

module Hako
  module Schedulers
    class EcsElb
      # @param [String] app_id
      # @param [Aws::ElasticLoadBalancing::Client] elb
      # @param [Array<Hash>] elb_configs
      # @param [Boolean] dry_run
      def initialize(app_id, elb, elb_configs, dry_run:)
        @app_id = app_id
        @elb = elb
        @elb_configs = elb_configs
        @dry_run = dry_run
      end

      # @param [String] name
      # @return [Aws::ElasticLoadBalancing::Types::LoadBalancerDescription]
      def describe_load_balancer(name)
        @elb.describe_load_balancers(load_balancer_names: [name]).load_balancer_descriptions[0]
      end

      # @return [Array<Aws::ElasticLoadBalancing::Types::LoadBalancerDescription>]
      def describe_load_balancers
        names = @elb_configs.map { |elb_config| elb_config.fetch('name', default_name) }
        @elb.describe_load_balancers(load_balancer_names: names).load_balancer_descriptions
      end

      # @param [Fixnum] front_port
      # @return [nil]
      def find_or_create_load_balancers(front_port)
        @elb_configs.map do |elb_config|
          name = elb_config.fetch('name', default_name)
          unless exist?(name)
            listeners = elb_config.fetch('listeners').map do |l|
              {
                protocol: l.fetch('protocol'),
                load_balancer_port: l.fetch('load_balancer_port'),
                instance_port: front_port,
                ssl_certificate_id: l.fetch('ssl_certificate_id', nil),
              }
            end
            lb = @elb.create_load_balancer(
              load_balancer_name: name,
              listeners: listeners,
              subnets: elb_config.fetch('subnets'),
              security_groups: elb_config.fetch('security_groups'),
              scheme: elb_config.fetch('scheme', nil),
              tags: elb_config.fetch('tags', {}).map { |k, v| { key: k, value: v.to_s } },
            )
            Hako.logger.info "Created ELB #{lb.dns_name} with instance_port=#{front_port}"
          end
          name
        end
      end

      # @return [nil]
      def destroy
        @elb_configs.each do |elb_config|
          name = elb_config.fetch('name', default_name)
          if exist?(name)
            if @dry_run
              Hako.logger.info("@elb.delete_load_balancer(load_balancer_name: #{name})")
            else
              @elb.delete_load_balancer(load_balancer_name: name)
              Hako.logger.info "Deleted ELB #{name}"
            end
          else
            Hako.logger.info "ELB #{name} doesn't exist"
          end
        end
      end

      # @param [String] name
      # @return [Boolean]
      def exist?(name)
        describe_load_balancer(name)
        true
      rescue Aws::ElasticLoadBalancing::Errors::LoadBalancerNotFound
        false
      end

      # @return [String]
      def default_name
        "hako-#{@app_id}"
      end
    end
  end
end
