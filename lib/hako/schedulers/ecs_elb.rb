# frozen_string_literal: true
require 'aws-sdk'
require 'hako'

module Hako
  module Schedulers
    class EcsElb
      # @param [String] app_id
      # @param [String] region
      # @param [Hash] elb_config
      # @param [Boolean] dry_run
      def initialize(app_id, region, elb_config, dry_run:)
        @app_id = app_id
        @elb = Aws::ElasticLoadBalancing::Client.new(region: region)
        @elb_config = elb_config
        @dry_run = dry_run
      end

      # @param [Aws::ECS::Types::LoadBalancer] ecs_lb
      # @return [nil]
      def show_status(ecs_lb)
        lb = describe_load_balancer
        lb.listener_descriptions.each do |ld|
          l = ld.listener
          puts "  #{lb.dns_name}:#{l.load_balancer_port} -> #{ecs_lb.container_name}:#{ecs_lb.container_port}"
        end
      end

      # @return [Aws::ElasticLoadBalancing::Types::LoadBalancerDescription]
      def describe_load_balancer
        @elb.describe_load_balancers(load_balancer_names: [name]).load_balancer_descriptions[0]
      end

      # @param [Fixnum] front_port
      # @return [Boolean]
      def find_or_create_load_balancer(front_port)
        unless @elb_config
          return false
        end

        unless exist?
          listeners = @elb_config.fetch('listeners').map do |l|
            {
              protocol: l.fetch('protocol'),
              load_balancer_port: l.fetch('load_balancer_port'),
              instance_port: front_port,
              ssl_certificate_id: l.fetch('ssl_certificate_id', nil),
            }
          end
          tags = @elb_config.fetch('tags', {}).map { |k, v| { key: k, value: v.to_s } }
          lb = @elb.create_load_balancer(
            load_balancer_name: name,
            listeners: listeners,
            subnets: @elb_config.fetch('subnets'),
            security_groups: @elb_config.fetch('security_groups'),
            scheme: @elb_config.fetch('scheme', nil),
            tags: tags.empty? ? nil : tags,
          )
          Hako.logger.info "Created ELB #{lb.dns_name} with instance_port=#{front_port}"
        end
        true
      end

      # @return [Types::ModifyLoadBalancerAttributesOutput, nil]
      def modify_attributes
        if @elb_config.key?('cross_zone_load_balancing')
          @elb.modify_load_balancer_attributes(
            load_balancer_name: name,
            load_balancer_attributes: {
              cross_zone_load_balancing: {
                enabled: @elb_config['cross_zone_load_balancing'],
              }
            }
          )
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

      # @return [Hash]
      def load_balancer_params_for_service
        { load_balancer_name: name }
      end
    end
  end
end
