{
  app: {
    image: 'app-image',
  },
  sidecars: {
    front: {
      type: 'nginx',
      image_tag: 'front-image',
    },
  },
}
