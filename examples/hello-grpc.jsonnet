{
  scheduler: {
    type: 'ecs',
    region: 'ap-northeast-1',
    cluster: 'eagletmt',
    desired_count: 2,
    role: 'ecsServiceRole',
    elb_v2: {
      // Specify protocol_version for gRPC servers
      protocol_version: 'GRPC',
      // VPC id where the target group is located
      vpc_id: 'vpc-WWWWWWWW',
      // If you want internal ELB, then use 'scheme'. (ex. internal service that like microservice inside VPC)
      scheme: 'internal',
      // Health check path of the target group
      health_check_path: '/AWS.ELB/healthcheck',
      listeners: [
        {
          port: 50051,
          protocol: 'HTTPS',
          certificate_arn: 'arn:aws:acm:ap-northeast-1:012345678901:certificate/01234567-89ab-cdef-0123-456789abcdef',
        },
      ],
      subnets: ['subnet-XXXXXXXX', 'subnet-YYYYYYYY'],
      security_groups: ['sg-ZZZZZZZZ'],
      load_balancer_attributes: {
        'access_logs.s3.enabled': 'true',
        'access_logs.s3.bucket': 'hako-access-logs',
        'access_logs.s3.prefix': 'hako-hello-grpc',
      },
      target_group_attributes: {
        // http://docs.aws.amazon.com/en_us/elasticloadbalancing/latest/application/load-balancer-target-groups.html#target-group-attributes
        'deregistration_delay.timeout_seconds': '20',
      },
      // Route ELB traffic to app container directly
      container_name: 'app',
      container: 50051,
    },
  },
  app: {
    image: 'awesome-grpc-server',
    memory: 128,
    cpu: 256,
    env: {
      PORT: '50051',
    },
    secrets: [{
      name: 'MESSAGE',
      value_from: 'arn:aws:ssm:ap-northeast-1:012345678901:parameter/hako/hello-grpc/secret-message',
    }],
    port_mappings: [
      {
        container_port: 50051,
        host_port: 0,
        protocol: 'tcp',
      },
    ],
  },
  scripts: [],
}
