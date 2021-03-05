# frozen_string_literal: true

require 'aws-sdk-elasticloadbalancingv2'
require 'hako'
require 'hako/error'

module Hako
  module Schedulers
    class EcsElbV2
      # @param [String] app_id
      # @param [String] region
      # @param [Hash] elb_v2_config
      # @param [Boolean] dry_run
      def initialize(app_id, region, elb_v2_config, dry_run:)
        @app_id = app_id
        @region = region
        @elb_v2_config = elb_v2_config
        @dry_run = dry_run
      end

      # @param [Aws::ECS::Types::LoadBalancer] ecs_lb
      # @return [nil]
      def show_status(ecs_lb)
        lb = describe_load_balancer
        elb_client.describe_listeners(load_balancer_arn: lb.load_balancer_arn).each do |page|
          page.listeners.each do |listener|
            puts "  #{lb.dns_name}:#{listener.port} -> #{ecs_lb.container_name}:#{ecs_lb.container_port}"
          end
        end
      end

      # @return [Aws::ElasticLoadBalancingV2::Types::LoadBalancer]
      def describe_load_balancer
        elb_client.describe_load_balancers(names: [elb_name]).load_balancers[0]
      rescue Aws::ElasticLoadBalancingV2::Errors::LoadBalancerNotFound
        nil
      end

      # @return [Aws::ElasticLoadBalancingV2::Types::TargetGroup]
      def describe_target_group
        elb_client.describe_target_groups(names: [target_group_name]).target_groups[0]
      rescue Aws::ElasticLoadBalancingV2::Errors::TargetGroupNotFound
        nil
      end

      # @param [Fixnum] front_port
      # @return [nil]
      def find_or_create_load_balancer(_front_port)
        unless @elb_v2_config
          return false
        end

        load_balancer = describe_load_balancer
        if !load_balancer_given? && !load_balancer
          tags = @elb_v2_config.fetch('tags', {}).map { |k, v| { key: k, value: v.to_s } }

          elb_type = @elb_v2_config.fetch('type', nil)
          if elb_type == 'network'
            load_balancer = elb_client.create_load_balancer(
              name: elb_name,
              subnets: @elb_v2_config.fetch('subnets'),
              scheme: @elb_v2_config.fetch('scheme', nil),
              type: 'network',
              tags: tags.empty? ? nil : tags,
            ).load_balancers[0]
            Hako.logger.info "Created ELBv2(NLB) #{load_balancer.dns_name}"
          else
            load_balancer = elb_client.create_load_balancer(
              name: elb_name,
              subnets: @elb_v2_config.fetch('subnets'),
              security_groups: @elb_v2_config.fetch('security_groups'),
              scheme: @elb_v2_config.fetch('scheme', nil),
              type: @elb_v2_config.fetch('type', nil),
              tags: tags.empty? ? nil : tags,
            ).load_balancers[0]
            Hako.logger.info "Created ELBv2 #{load_balancer.dns_name}"
          end
        end

        target_group = describe_target_group
        if !target_group_given? && !target_group
          elb_type = @elb_v2_config.fetch('type', nil)
          target_group = if elb_type == 'network'
                           elb_client.create_target_group(
                             name: target_group_name,
                             port: 80,
                             protocol: 'TCP',
                             vpc_id: @elb_v2_config.fetch('vpc_id'),
                             target_type: @elb_v2_config.fetch('target_type', nil),
                             healthy_threshold_count: @elb_v2_config.fetch('healthy_threshold_count', nil),
                             unhealthy_threshold_count: @elb_v2_config.fetch('unhealthy_threshold_count', nil),
                           ).target_groups[0]
                         else
                           matcher =
                             if @elb_v2_config.key?('matcher')
                               {
                                 http_code: @elb_v2_config.fetch('matcher')['http_code'],
                                 grpc_code: @elb_v2_config.fetch('matcher')['grpc_code'],
                               }
                             end
                           elb_client.create_target_group(
                             name: target_group_name,
                             port: 80,
                             protocol: 'HTTP',
                             protocol_version: @elb_v2_config.fetch('protocol_version', 'HTTP1'),
                             vpc_id: @elb_v2_config.fetch('vpc_id'),
                             health_check_path: @elb_v2_config.fetch('health_check_path', nil),
                             health_check_timeout_seconds: @elb_v2_config.fetch('health_check_timeout_seconds', nil),
                             healthy_threshold_count: @elb_v2_config.fetch('healthy_threshold_count', nil),
                             health_check_interval_seconds: elb_v2_config.fetch('health_check_interval_seconds', nil),
                             unhealthy_threshold_count: elb_v2_config.fetch('unhealthy_threshold_count', nil),
                             target_type: @elb_v2_config.fetch('target_type', nil),
                             matcher: matcher,
                           ).target_groups[0]
                         end

          Hako.logger.info "Created target group #{target_group.target_group_arn}"
        end

        unless load_balancer_given?
          listener_ports = elb_client.describe_listeners(load_balancer_arn: load_balancer.load_balancer_arn).flat_map { |page| page.listeners.map(&:port) }
          @elb_v2_config.fetch('listeners').each do |l|
            params = {
              load_balancer_arn: load_balancer.load_balancer_arn,
              protocol: l.fetch('protocol'),
              port: l.fetch('port'),
              ssl_policy: l['ssl_policy'],
              default_actions: [{ type: 'forward', target_group_arn: target_group.target_group_arn }],
            }
            certificate_arn = l.fetch('certificate_arn', nil)
            if certificate_arn
              params[:certificates] = [{ certificate_arn: certificate_arn }]
            end

            unless listener_ports.include?(params[:port])
              listener = elb_client.create_listener(params).listeners[0]
              Hako.logger.info("Created listener #{listener.listener_arn}")
            end
          end
        end

        true
      end

      # @return [nil]
      def modify_attributes
        unless @elb_v2_config
          return nil
        end

        unless load_balancer_given?
          load_balancer = describe_load_balancer
          subnets = @elb_v2_config.fetch('subnets').sort
          if load_balancer && subnets != load_balancer.availability_zones.map(&:subnet_id).sort
            if @dry_run
              Hako.logger.info("elb_client.set_subnets(load_balancer_arn: #{load_balancer.load_balancer_arn}, subnets: #{subnets}) (dry-run)")
            else
              Hako.logger.info("Updating ELBv2 subnets to #{subnets}")
              elb_client.set_subnets(load_balancer_arn: load_balancer.load_balancer_arn, subnets: subnets)
            end
          end

          new_listeners = @elb_v2_config.fetch('listeners')
          if load_balancer
            current_listeners = elb_client.describe_listeners(load_balancer_arn: load_balancer.load_balancer_arn).listeners
            new_listeners.each do |new_listener|
              current_listener = current_listeners.find { |l| l.port == new_listener['port'] }
              if current_listener && new_listener['ssl_policy'] && new_listener['ssl_policy'] != current_listener.ssl_policy
                if @dry_run
                  Hako.logger.info("elb_client.modify_listener(listener_arn: #{current_listener.listener_arn}, ssl_policy: #{new_listener['ssl_policy']}) (dry-run)")
                else
                  Hako.logger.info("Updating ELBv2 listener #{new_listener['port']} ssl_policy to #{new_listener['ssl_policy']}")
                  elb_client.modify_listener(listener_arn: current_listener.listener_arn, ssl_policy: new_listener['ssl_policy'])
                end
              end
            end
          end

          if @elb_v2_config.key?('load_balancer_attributes')
            attributes = @elb_v2_config.fetch('load_balancer_attributes').map { |key, value| { key: key, value: value } }
            if @dry_run
              if load_balancer
                Hako.logger.info("elb_client.modify_load_balancer_attributes(load_balancer_arn: #{load_balancer.load_balancer_arn}, attributes: #{attributes.inspect}) (dry-run)")
              else
                Hako.logger.info("elb_client.modify_load_balancer_attributes(load_balancer_arn: unknown, attributes: #{attributes.inspect}) (dry-run)")
              end
            else
              Hako.logger.info("Updating ELBv2 attributes to #{attributes.inspect}")
              elb_client.modify_load_balancer_attributes(load_balancer_arn: load_balancer.load_balancer_arn, attributes: attributes)
            end
          end
        end

        unless target_group_given?
          if @elb_v2_config.key?('target_group_attributes')
            target_group = describe_target_group
            attributes = @elb_v2_config.fetch('target_group_attributes').map { |key, value| { key: key, value: value } }
            if @dry_run
              if target_group
                Hako.logger.info("elb_client.modify_target_group_attributes(target_group_arn: #{target_group.target_group_arn}, attributes: #{attributes.inspect}) (dry-run)")
              else
                Hako.logger.info("elb_client.modify_target_group_attributes(target_group_arn: unknown, attributes: #{attributes.inspect}) (dry-run)")
              end
            else
              Hako.logger.info("Updating target group attributes to #{attributes.inspect}")
              elb_client.modify_target_group_attributes(target_group_arn: target_group.target_group_arn, attributes: attributes)
            end
          end
        end
        nil
      end

      # @return [nil]
      def destroy
        unless @elb_v2_config
          return false
        end

        unless load_balancer_given?
          load_balancer = describe_load_balancer
          if load_balancer
            if @dry_run
              Hako.logger.info("elb_client.delete_load_balancer(load_balancer_arn: #{load_balancer.load_balancer_arn})")
            else
              elb_client.delete_load_balancer(load_balancer_arn: load_balancer.load_balancer_arn)
              Hako.logger.info "Deleted ELBv2 #{load_balancer.load_balancer_arn}"
            end
          else
            Hako.logger.info "ELBv2 #{elb_name} doesn't exist"
          end
        end

        unless target_group_given?
          target_group = describe_target_group
          if target_group
            if @dry_run
              Hako.logger.info("elb_client.delete_target_group(target_group_arn: #{target_group.target_group_arn})")
            else
              deleted = false
              30.times do
                begin
                  elb_client.delete_target_group(target_group_arn: target_group.target_group_arn)
                  deleted = true
                  break
                rescue Aws::ElasticLoadBalancingV2::Errors::ResourceInUse => e
                  Hako.logger.warn("#{e.class}: #{e.message}")
                end
                sleep 1
              end
              unless deleted
                raise Error.new("Cannot delete target group #{target_group.target_group_arn}")
              end

              Hako.logger.info "Deleted target group #{target_group.target_group_arn}"
            end
          end
        end
      end

      # @return [String]
      def elb_name
        @elb_v2_config.fetch('load_balancer_name', "hako-#{@app_id}")
      end

      # @return [Boolean]
      def load_balancer_given?
        @elb_v2_config.key?('load_balancer_name')
      end

      # @return [String]
      def target_group_name
        @elb_v2_config.fetch('target_group_name', "hako-#{@app_id}")
      end

      # @return [Boolean]
      def target_group_given?
        @elb_v2_config.key?('target_group_name')
      end

      # @return [Hash]
      def load_balancer_params_for_service
        {
          target_group_arn: describe_target_group.target_group_arn,
          container_name: @elb_v2_config.fetch('container_name', 'front'),
          container_port: @elb_v2_config.fetch('container_port', 80),
        }
      end

      private

      def elb_client
        @elb_v2 ||= Aws::ElasticLoadBalancingV2::Client.new(region: @region)
      end
    end
  end
end
