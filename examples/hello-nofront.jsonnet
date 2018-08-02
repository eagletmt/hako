local fileProvider = std.native('provide.file');
local provide(name) = fileProvider(std.toString({ path: 'hello.env' }), name);

{
  scheduler: {
    type: 'ecs',
    region: 'ap-northeast-1',
    cluster: 'eagletmt',
    desired_count: 2,
    role: 'ecsServiceRole',
    elb_v2: {
      // VPC id where the target group is located
      vpc_id: 'vpc-WWWWWWWW',
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
      // Connect ELB to app container
      container_name: 'app',
      container_port: 3000,
    },
  },
  app: {
    image: 'ryotarai/hello-sinatra',
    memory: 128,
    cpu: 256,
    env: {
      PORT: '3000',
      MESSAGE: std.format('%s-san', provide('username')),
    },
    // Add port mapping to connect to ELB
    port_mappings: [
      {
        container_port: 3000,
        host_port: 0,
        protocol: 'tcp',
      },
    ],
  },
}
