{
  scheduler: {
    type: 'ecs',
    region: 'ap-northeast-1',
    cluster: 'eagletmt',
    desired_count: 1,
    role: 'ECSServiceRole',
    elb_v2: {
      vpc_id: 'vpc-11111111',
      health_check_path: '/site/sha',
      listeners: [
        {
          port: 80,
          protocol: 'HTTP',
        },
        {
          port: 443,
          protocol: 'HTTPS',
          certificate_arn: 'arn:aws:acm:ap-northeast-1:012345678901:certificate/01234567-89ab-cdef-0123-456789abcdef',
        },
      ],
      subnets: [
        'subnet-11111111',
        'subnet-22222222',
      ],
      security_groups: [
        'sg-11111111',
      ],
    },
  },
  app: {
    image: 'busybox',
    cpu: 32,
    memory: 64,
  },
}
