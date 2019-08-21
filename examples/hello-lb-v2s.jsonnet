{
  scheduler: {
    type: 'ecs',
    region: 'ap-northeast-1',
    cluster: 'eagletmt',
    desired_count: 2,
    role: 'ecsServiceRole',
    // dynamic_port_mapping is enabled by default with elb_v2
    // dynamic_port_mapping: false,
    // health_check_grace_period_seconds: 0,
    elb_v2s: [{
      // VPC id where the target group is located
      vpc_id: 'vpc-WWWWWWWW',
      // If you want internal ELB, then use 'scheme'. (ex. internal service that like microservice inside VPC)
      // scheme: internal
      // Health check path of the target group
      health_check_path: '/site/sha',
      listeners: [
        {
          port: 80,
          protocol: 'HTTP',
        },
        {
          port: 443,
          protocol: 'HTTPS',
          certificate_arn: 'arn:aws:iam::012345678901:server-certificate/hello-lb-v2.example.com',
        },
      ],
      subnets: ['subnet-XXXXXXXX', 'subnet-YYYYYYYY'],
      security_groups: ['sg-ZZZZZZZZ'],
      load_balancer_attributes: {
        'access_logs.s3.enabled': 'true',
        'access_logs.s3.bucket': 'hako-access-logs',
        'access_logs.s3.prefix': 'hako-hello-lb-v2',
      },
      target_group_attributes: {
        // http://docs.aws.amazon.com/en_us/elasticloadbalancing/latest/application/load-balancer-target-groups.html#target-group-attributes
        'deregistration_delay.timeout_seconds': '20',
      },
    },
  },
  {
      // VPC id where the target group is located
      vpc_id: 'vpc-WWWWWWWW',
      // If you want internal ELB, then use 'scheme'. (ex. internal service that like microservice inside VPC)
      // scheme: internal
      // Health check path of the target group
      health_check_path: '/site/stats',
      listeners: [
        {
          port: 8888,
          protocol: 'HTTP',
        },
      ],
      subnets: ['subnet-XXXXXXXX', 'subnet-YYYYYYYY'],
      security_groups: ['sg-ZZZZZZZZ'],
      load_balancer_attributes: {
        'access_logs.s3.enabled': 'true',
        'access_logs.s3.bucket': 'hako-access-logs',
        'access_logs.s3.prefix': 'hako-hello-lb-v2',
      },
      target_group_attributes: {
        // http://docs.aws.amazon.com/en_us/elasticloadbalancing/latest/application/load-balancer-target-groups.html#target-group-attributes
        'deregistration_delay.timeout_seconds': '20',
      },
    },
  }],
  app: {
    image: 'ryotarai/hello-sinatra',
    memory: 128,
    cpu: 256,
    env: {
      PORT: '3000',
    },
    secrets: [{
      name: 'MESSAGE',
      value_from: 'arn:aws:ssm:ap-northeast-1:012345678901:parameter/hako/hello-lb-v2/secret-message',
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
