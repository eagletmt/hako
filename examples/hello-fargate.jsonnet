local appId = std.extVar('appId');

local region = 'us-east-1';
local publicSubnets = ['subnet-xxxxxxxx', 'subnet-yyyyyyyy'];
local privateSubnets = ['subnet-zzzzzzzz', 'subnet-wwwwwwww'];
local elbSecurityGroups = ['sg-xxxxxxxx'];
local taskSecurityGroups = ['sg-yyyyyyyy', 'sg-zzzzzzzz'];
local awslogs = {
  log_driver: 'awslogs',
  options: {
    'awslogs-group': std.format('/ecs/%s', appId),
    'awslogs-region': region,
    'awslogs-stream-prefix': 'ecs',
  },
};

{
  scheduler: {
    type: 'ecs',
    region: region,
    cluster: 'eagletmt',
    desired_count: 1,
    task_role_arn: 'arn:aws:iam::012345678901:role/EcsDefault',
    elb_v2: {
      vpc_id: 'vpc-xxxxxxxx',
      health_check_path: '/site/sha',
      listeners: [
        {
          port: 80,
          protocol: 'HTTP',
        },
        {
          port: 443,
          protocol: 'HTTPS',
          certificate_arn: 'arn:aws:acm:us-east-1:012345678901:certificate/01234567-89ab-cdef-0123-456789abcdef',
        },
      ],
      subnets: publicSubnets,
      security_groups: elbSecurityGroups,
      load_balancer_attributes: {
        'access_logs.s3.enabled': 'true',
        'access_logs.s3.bucket': 'hako-access-logs',
        'access_logs.s3.prefix': std.format('hako-%s', appId),
        'idle_timeout.timeout_seconds': '5',
      },
      target_group_attributes: {
        'deregistration_delay.timeout_seconds': '20',
      },
    },
    // Fargate
    execution_role_arn: 'arn:aws:iam::012345678901:role/ecsTaskExecutionRole',
    cpu: '1024',
    memory: '2048',
    requires_compatibilities: ['FARGATE'],
    network_mode: 'awsvpc',
    launch_type: 'FARGATE',
    network_configuration: {
      awsvpc_configuration: {
        subnets: privateSubnets,
        security_groups: taskSecurityGroups,
        assign_public_ip: 'DISABLED',
      },
    },
  },
  app: {
    image: 'ryotarai/hello-sinatra',
    cpu: 128,
    memory: 256,
    env: {
      PORT: '3000',
      MESSAGE: 'Hello, Fargate',
    },
    log_configuration: awslogs,
  },
  sidecars: {
    front: {
      image_tag: 'hako-nginx',
      log_configuration: awslogs,
    },
  },
  scripts: [
    (import 'front.libsonnet') + { backend_port: 3000 },
  ],
}
