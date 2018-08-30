{
  app: {
    image: 'app-image',
    links: ['redis'],
  },
  sidecars: {
    redis: {
      image_tag: 'redis',
      links: ['memcached'],
    },
    memcached: {
      image_tag: 'memcached',
    },
    fluentd: {
      image_tag: 'fluentd',
      links: ['redis'],
    },
  },
}
