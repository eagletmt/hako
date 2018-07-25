{
  scheduler: {
    type: 'ecs',
    region: 'ap-northeast-1',
    cluster: 'eagletmt',
    desired_count: 2,
    role: 'ecsServiceRole',
    autoscaling_group_for_oneshot: 'hako-batch-cluster',
  },
  app: {
    image: 'ryotarai/hello-sinatra',
    memory: 128,
    cpu: 256,
    env: {
      PORT: '3000',
      MESSAGE: 'hello',
    },
    command: ['echo', 'heavy offline job'],
  },
}
