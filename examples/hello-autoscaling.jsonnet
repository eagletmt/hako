local fileProvider = std.native('provide.file');
local provide(name) = fileProvider(std.toString({ path: 'hello.env' }), name);

{
  scheduler: {
    type: 'ecs',
    region: 'ap-northeast-1',
    cluster: 'eagletmt',
    desired_count: 2,
    role: 'ecsServiceRole',
    elb: {
      listeners: [
        {
          load_balancer_port: 80,
          protocol: 'HTTP',
        },
      ],
      subnets: [
        'subnet-XXXXXXXX',
        'subnet-YYYYYYYY',
      ],
      security_groups: [
        'sg-ZZZZZZZZ',
      ],
    },
    autoscaling: {
      role_arn: 'arn:aws:iam::012345678901:role/ecsAutoscaleRole',
      min_capacity: 1,
      max_capacity: 4,
      policies: [
        // Add one task when ecs-scaling-out-hello-autoscaling-service is in alarm state
        {
          alarms: ['ecs-scaling-out-hello-autoscaling-service'],
          cooldown: 300,
          adjustment_type: 'ChangeInCapacity',
          scaling_adjustment: 1,
          metric_interval_lower_bound: 0,
          metric_aggregation_type: 'Average',
        },
        // Remove one task when ecs-scaling-in-hello-autoscaling-service is in alarm state
        {
          alarms: ['ecs-scaling-in-hello-autoscaling-service'],
          cooldown: 300,
          adjustment_type: 'ChangeInCapacity',
          scaling_adjustment: -1,
          metric_interval_upper_bound: 0,
          metric_aggregation_type: 'Average',
        },
        // Adjust the numer of tasks to keep the metric close to the target value
        {
          policy_type: 'TargetTrackingScaling',
          name: 'ecs-target-tracking-scaling-hello-autoscaling-service',
          target_value: 50,
          predefined_metric_type: 'ECSServiceAverageCPUUtilization',
          scale_out_cooldown: 300,
          scale_in_cooldown: 300,
        },
      ],
    },
  },
  app: {
    image: 'ryotarai/hello-sinatra',
    memory: 128,
    cpu: 256,
    env: {
      PORT: '3000',
      MESSAGE: std.format('%s-san', provide('username')),
    },
  },
  sidecars: {
    front: {
      image_tag: 'hako-nginx',
      memory: 32,
      cpu: 32,
    },
  },
  scripts: [
    (import 'front.libsonnet') + {
      backend_port: 3000,
      locations: {
        '/': {
          allow_only_from: ['10.0.0.0/24'],
        },
      },
    },
  ],
}
