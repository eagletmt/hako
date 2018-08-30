{
  app: {
    image: 'app-image',
    volumes_from: [
      { source_container: 'redis' },
    ],
  },
  sidecars: {
    redis: {
      image_tag: 'redis',
      volumes_from: [
        { source_container: 'memcached' },
      ],
    },
    memcached: {
      image_tag: 'memcached',
    },
    fluentd: {
      image_tag: 'fluentd',
      volumes_from: [
        { source_container: 'redis' },
      ],
    },
  },
}
