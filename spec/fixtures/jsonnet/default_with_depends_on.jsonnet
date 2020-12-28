{
  app: {
    image: 'app-image',
    depends_on: [
      { container_name: 'redis', condition: 'STARTED' },
    ],
  },
  sidecars: {
    redis: {
      image_tag: 'redis',
      depends_on: [
        { container_name: 'memcached', condition: 'STARTED' },
      ],
    },
    memcached: {
      image_tag: 'memcached',
    },
    fluentd: {
      image_tag: 'fluentd',
      depends_on: [
        { container_name: 'redis', condition: 'STARTED' },
      ],
    },
  },
}
