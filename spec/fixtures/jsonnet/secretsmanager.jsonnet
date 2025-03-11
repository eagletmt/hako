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
        name: 'SECRET_VALUE',
        value_from: 'arn:aws:secretsmanager:ap-northeast-1:012345678901:secret:hoge/fuga1-abcdef:::',
      },
      {
        name: 'SECRET_MESSAGE1',
        value_from: 'arn:aws:secretsmanager:ap-northeast-1:012345678901:secret:hoge/fuga2-abcdef:SECRET_MESSAGE1::',
      },
      {
        name: 'SECRET_MESSAGE2',
        value_from: 'arn:aws:secretsmanager:ap-northeast-1:012345678901:secret:hoge/fuga2-abcdef:SECRET_MESSAGE2::',
      },
      {
        name: 'SECRET_MESSAGE3',
        value_from: 'arn:aws:secretsmanager:us-east-1:012345678901:secret:hoge/fuga3-abcdef:SECRET_MESSAGE3::',
      },
    ],
  },
}
