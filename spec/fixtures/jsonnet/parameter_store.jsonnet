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
    secrets: [
      {
        name: 'SECRET_MESSAGE1',
        value_from: 'arn:aws:ssm:ap-northeast-1:012345678901:parameter/hoge/fuga/SECRET_MESSAGE1',
      },
      {
        name: 'SECRET_MESSAGE2',
        value_from: 'arn:aws:ssm:ap-northeast-1:012345678901:parameter/hoge/fuga/SECRET_MESSAGE2',
      },
      {
        name: 'SECRET_MESSAGE3',
        value_from: 'arn:aws:ssm:us-east-1:012345678901:parameter/hoge/fuga/SECRET_MESSAGE3',
      },
    ],
  },
}
