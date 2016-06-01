# frozen_string_literal: true
require 'aws-sdk'
require 'hako'

module Hako
  module Schedulers
    class EcsElb
      # @param [String] app_id
      # @param [Aws::ElasticLoadBalancing::Client] elb
      # @param [Hash] elb_config
      # @param [Boolean] dry_run
      def initialize(app_id, elb, elb_config, dry_run:)
        @app_id = app_id
        @elb = elb
        @elb_config = elb_config
        @dry_run = dry_run
      end

      # @return [Aws::ElasticLoadBalancing::Types::LoadBalancerDescription]
      def describe_load_balancer
        @elb.describe_load_balancers(load_balancer_names: [name]).load_balancer_descriptions[0]
      end

      # @param [Fixnum] front_port
      # @return [nil]
      def find_or_create_load_balancer(front_port)
        if @elb_config
          unless exist?
            listeners = @elb_config.fetch('listeners').map do |l|
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
              subnets: @elb_config.fetch('subnets'),
              security_groups: @elb_config.fetch('security_groups'),
              scheme: @elb_config.fetch('scheme', nil),
              tags: @elb_config.fetch('tags', {}).map { |k, v| { key: k, value: v.to_s } },
            )
            Hako.logger.info "Created ELB #{lb.dns_name} with instance_port=#{front_port}"
          end
          name
        end
      end

      # @return [nil]
      def destroy
        if exist?
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

      # @return [Boolean]
      def exist?
        describe_load_balancer
        true
      rescue Aws::ElasticLoadBalancing::Errors::LoadBalancerNotFound
        false
      end

      # @return [String]
      def name
        "hako-#{@app_id}"
      end
    end
  end
end
