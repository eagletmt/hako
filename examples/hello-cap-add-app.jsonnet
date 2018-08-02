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
    command: ['echo', 'hello with SYS_RAWIO'],
    linux_parameters: {
      capabilities: {
        add: ['SYS_RAWIO'],
      },
    },
  },
}
