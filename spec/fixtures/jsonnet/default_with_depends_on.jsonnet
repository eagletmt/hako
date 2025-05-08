{
  app: {
    image: 'app-image',
    links: ['redis'],
    depends_on: [
      { container_name: 'init2', condition: 'SUCCESS' },
    ],
    mount_points: [
      { source_volume: 'data', container_path: '/data', read_only: true },
    ],
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
    init: {
      essential: false,
      image_tag: 'busybox',
      command: ['mkdir', '-p', '/data/mydir'],
      mount_points: [
        { source_volume: 'data', container_path: '/data' },
      ],
    },
    init2: {
      essential: false,
      image_tag: 'busybox',
      command: ['touch', '/data/mydir/ok.txt'],
      depends_on: [
        { container_name: 'init', condition: 'SUCCESS' },
      ],
      mount_points: [
        { source_volume: 'data', container_path: '/data' },
      ],
    },
  },
  volumes: {
    data: {},
  },
}
