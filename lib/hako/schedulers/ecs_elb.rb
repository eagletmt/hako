require 'aws-sdk'
require 'hako'

module Hako
  module Schedulers
    class EcsElb
      def initialize(app_id, elb, elb_config)
        @app_id = app_id
        @elb = elb
        @elb_config = elb_config
      end

      def describe_load_balancer
        @elb.describe_load_balancers(load_balancer_names: [name]).load_balancer_descriptions[0]
      end

      def find_or_create_load_balancer(front_port)
        if @elb_config
          unless exist?
            listeners = @elb_config.fetch('listeners').map do |l|
              {
                protocol: 'tcp',
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
              tags: @elb_config.fetch('tags', {}).map { |k, v| { key: k, value: v.to_s } },
            )
            Hako.logger.info "Created ELB #{lb.dns_name} with instance_port=#{front_port}"
          end
          name
        else
          nil
        end
      end

      private

      def name
        "hako-#{@app_id}"
      end

      def exist?
        @elb.describe_load_balancers(load_balancer_names: [name])
        true
      rescue Aws::ElasticLoadBalancing::Errors::LoadBalancerNotFound
        false
      end

    end
  end
end
