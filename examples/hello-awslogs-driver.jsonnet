{
  scheduler: {
    type: 'ecs',
    region: 'ap-northeast-1',
    cluster: 'eagletmt',
    desired_count: 1,
  },
  app: {
    image: 'busybox',
    memory: 128,
    cpu: 256,
    command: ['echo', 'hello awslogs'],
    log_configuration: {
      log_driver: 'awslogs',
      options: {
        'awslogs-group': 'my-logs',
        'awslogs-region': 'ap-northeast-1',
        'awslogs-stream-prefix': 'example',
      },
    },
  },
  scripts: [
    (import 'create_aws_cloud_watch_logs_log_group.libsonnet'),
  ],
}
