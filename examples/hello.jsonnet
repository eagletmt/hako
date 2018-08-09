local fileProvider = std.native('provide.file');
local provide(name) = fileProvider(std.toString({ path: 'hello.env' }), name);

{
  scheduler: {
    type: 'ecs',
    region: 'ap-northeast-1',
    cluster: 'eagletmt',
    desired_count: 2,
    task_role_arn: 'arn:aws:iam::012345678901:role/HelloRole',
    deployment_configuration: {
      maximum_percent: 200,
      minimum_healthy_percent: 50,
    },
  },
  app: {
    image: 'ryotarai/hello-sinatra',
    memory: 128,
    cpu: 256,
    health_check: {
      command: [
        'CMD-SHELL',
        'curl -f http://localhost:3000/ || exit 1',
      ],
      interval: 30,
      timeout: 5,
      retries: 3,
      start_period: 1,
    },
    links: [
      'redis:redis',
    ],
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
    redis: {
      image_tag: 'redis:3.0',
      cpu: 64,
      memory: 512,
    },
  },
  scripts: [
    (import 'front.libsonnet') + {
      backend_port: 3000,
    },
  ],
}
