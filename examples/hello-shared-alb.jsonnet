{
  scheduler: {
    type: 'ecs',
    region: 'ap-northeast-1',
    cluster: 'eagletmt',
    desired_count: 2,
    role: 'ecsServiceRole',
    elb_v2: {
      // Use existing load balancer
      load_balancer_name: 'hello-shared-alb',
      // VPC id where the target group is located
      vpc_id: 'vpc-WWWWWWWW',
      // Health check path of the target group
      health_check_path: '/site/sha',
      target_group_attributes: {
        // http://docs.aws.amazon.com/en_us/elasticloadbalancing/latest/application/load-balancer-target-groups.html#target-group-attributes
        'deregistration_delay.timeout_seconds': '20',
      },
    },
  },
  app: {
    image: 'ryotarai/hello-sinatra',
    memory: 128,
    cpu: 256,
    env: {
      PORT: '3000',
    },
    secrets: [{
      name: 'MESSAGE',
      value_from: 'arn:aws:ssm:ap-northeast-1:012345678901:parameter/hako/hello-shared-alb/secret-message',
    }],
  },
  sidecars: {
    front: {
      image_tag: 'hako-nginx',
      memory: 32,
      cpu: 32,
    },
  },
  scripts: [
    (import 'front.libsonnet') + {
      backend_port: 3000,
      locations: {
        '/': {
          allow_only_from: ['10.0.0.0/24'],
        },
      },
    },
  ],
}
