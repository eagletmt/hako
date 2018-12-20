{
  scheduler: {
    type: 'ecs',
    region: 'ap-northeast-1',
    cluster: 'eagletmt',
    desired_count: 1,
    role: 'ECSServiceRole',
    service_discovery: [
      {
        container_name: 'app',
        container_port: 80,
        service: {
          name: 'ecs-service-discovery',
          namespace_id: 'ns-1111111111111111',
          dns_config: {
            dns_records: [
              {
                type: 'SRV',
                ttl: 60,
              },
            ],
          },
          health_check_custom_config: {
            failure_threshold: 1,
          },
        },
      },
    ],
  },
  app: {
    image: 'busybox',
    cpu: 32,
    memory: 64,
  },
}
