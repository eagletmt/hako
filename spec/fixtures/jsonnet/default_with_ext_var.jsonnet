{
  app: {
    image: std.extVar('app_image'),
  },
  sidecars: {
    front: {
      type: 'nginx',
      image_tag: std.extVar('front_image'),
    },
  },
}
