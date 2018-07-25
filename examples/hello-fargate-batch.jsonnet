{
  scheduler: {
    type: 'ecs',
    region: 'us-east-1',
    cluster: 'eagletmt',
    // Fargate
    execution_role_arn: 'arn:aws:iam::012345678901:role/ecsTaskExecutionRole',
    cpu: '1024',
    memory: '2048',
    requires_compatibilities: ['FARGATE'],
    network_mode: 'awsvpc',
    launch_type: 'FARGATE',
    network_configuration: {
      awsvpc_configuration: {
        subnets: ['subnet-XXXXXXXX'],
        security_groups: [],
        assign_public_ip: 'DISABLED',
      },
    },
  },
  app: {
    image: 'ryotarai/hello-sinatra',
    cpu: 1024,
    memory: 256,
    memory_reservation: 128,
    log_configuration: {
      log_driver: 'awslogs',
      options: {
        'awslogs-group': '/ecs/hello-fargate-batch',
        'awslogs-region': 'us-east-1',
        'awslogs-stream-prefix': 'ecs',
      },
    },
  },
  scripts: [
    (import './create_aws_cloud_watch_logs_log_group.libsonnet'),
  ],
}
