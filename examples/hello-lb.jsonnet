local fileProvider = std.native('provide.file');
local provide(name) = fileProvider(std.toString({ path: 'hello.env' }), name);

{
  scheduler: {
    type: 'ecs',
    region: 'ap-northeast-1',
    cluster: 'eagletmt',
    desired_count: 2,
    role: 'ecsServiceRole',
    // dynamic_port_mapping cannot be enabled with elb
    elb: {
      listeners: [
        {
          load_balancer_port: 80,
          protocol: 'HTTP',
        },
      ],
      subnets: ['subnet-XXXXXXXX', 'subnet-YYYYYYYY'],
      security_groups: ['sg-ZZZZZZZZ'],
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
