local fileProvider = std.native('provide.file');
local provide(name) = fileProvider(std.toString({ path: 'hello.env' }), name);

{
  scheduler: {
    type: 'ecs',
    region: 'ap-northeast-1',
    cluster: 'eagletmt',
    desired_count: 2,
    role: 'ecsServiceRole',
    service_discovery: [
      {
        container_name: 'app',
        container_port: 80,
        service: {
          name: 'hello-service-discovery',
          namespace_id: 'ns-XXXXXXXXXXXXXXXX',
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
    image: 'ryotarai/hello-sinatra',
    memory: 128,
    cpu: 256,
    env: {
      PORT: '3000',
      MESSAGE: std.format('%s-san', provide('username')),
    },
    port_mappings: [
      {
        container_port: 3000,
        host_port: 0,
        protocol: 'tcp',
      },
    ],
  },
}
