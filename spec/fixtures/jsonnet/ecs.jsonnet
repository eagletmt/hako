{
  scheduler: {
    type: 'ecs',
    region: 'ap-northeast-1',
    cluster: 'eagletmt',
    desired_count: 1,
    role: 'ECSServiceRole',
  },
  app: {
    image: 'busybox',
    cpu: 32,
    memory: 64,
  },
}
