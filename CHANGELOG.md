# 2.16.0 (2020-11-02)
## New features
- Support for parameters in elbv2 
  - `health_check_timeout_seconds`
  - `health_check_interval_seconds`
  - `healthy_threshold_count`
  - `unhealthy_threshold_count`

# 2.15.0 (2020-11-02)
## New features
- Support protocol_version and matcher option of ALB target groups

# 2.14.0 (2020-05-20)
## New features
- Support tags for task definition and propagate them to ECS tasks
    - Now all created ECS services and launched ECS tasks have `propagate_tags=TASK_DEFINITION` parameter.
- Support repository_credentials

# 2.13.0 (2020-01-10)
## New features
- Support capacity provider strategy

## Bug fixes
- Do not try to update assign_public_ip when it is not changed

# 2.12.0 (2019-09-09)
## New features
- Support more overrides options for `hako oneshot`
  - `--app-cpu`, `--app-memory` and `--app-memory-reservation` are added

## Bug fixes
- Show `--health-*` options in dry-run

# 2.11.1 (2019-05-17)
## Bug fixes
- Fix comparison of `system_controls` parameter

# 2.11.0 (2019-05-17)
## New features
- Support `system_controls` parameter in container definition

# 2.10.0 (2019-05-09)
## New features
- Support `depends_on` parameter in container definition

# 2.9.2 (2019-04-10)
## Bug fixes
- Change threshold for detecting a deployment failure
  - See [this commit](https://github.com/eagletmt/hako/commit/12e27259dc2f0317f8b2c1156b66572c88a3801e) for details

# 2.9.1 (2019-04-04)
## Bug fixes
- Skip creating load balancer on dry-run
  - Regression in v2.9.0

# 2.9.0 (2019-04-03)
## New features
- Add `remove_starting` method to Hako::Script which is called when `hako remove` starts
- Support sharing load balancers
  - When `elb_v2` field has `load_balancer_name` but doesn't have `target_group_name`, hako will manage only the target group and doesn't touch the load balancer.
  - This is useful when one load balancer is shared with multiple target groups and some of them is deployed by hako.
  - See [examples/hello-shared-alb.jsonnet](examples/hello-shared-alb.jsonnet)

## Changes
- When `load_balancer_name` is specified and `target_group_name` is not, the default `target_group_name` is changed from `load_balancer_name` to `hako-#{app_id}`.
  - If you use `load_balancer_name` field only, you must specify `target_group_name` field too.

# 2.8.0 (2019-03-17)
## New features
- Add `deploy_failed` method to Hako::Script which is called when `hako deploy` fails
- Add .app.tag field to definition to specify the default value of app container's tag
  - The default value was fixed to "latest", but you can now specify custom default value.

# 2.7.0 (2019-03-15)
## New features
- Support `entry_point` parameter
- Support ECS Service Discovery
  - See [examples/hello-service-discovery.jsonnet](examples/hello-service-discovery.jsonnet)

# 2.6.2 (2018-12-19)
## Bug fixes
- Set `platform_version` correctly

# 2.6.1 (2018-12-17)
## Bug fixes
- Avoid updating service when `platform_version` is not specified
- Keep essential parameter in `hako oneshot`

## Improvements
- Show more information about tasks in `hako status`

# 2.6.0 (2018-12-13)
## New features
- Support `essential` parameter for each container
  - The default value remains `true`

## Bug fixes
- Stop trying to deregister non-existent scalable target on `hako remove`
- Update service when `health_check_grace_period_seconds` changes

# 2.5.1 (2018-11-29)
## Bug fixes
- Check secrets existence in dry-run mode

# 2.5.0 (2018-11-22)
## New features
- Add `load_balancer_name` and `target_group_name` option to skip creating ELB
- Support ECS secrets

# 2.4.0 (2018-11-13)
## New features
- Support `readonly_root_filesystem` parameter
- Support `docker_security_options` parameter
- Support `ssl_policy` option in `elb_v2`

## Bug fixes
- Skip updating `desired_count` before removing service using daemon scheduling strategy

# 2.3.1 (2018-09-26)
## Changes
- Change show-definition output from YAML to JSON
  - The show-definition output is still parsable as YAML

## Bug fixes
- Set `deployment_configuration` to nil when absent

# 2.3.0 (2018-08-30)
## New features
- Support `health_check` parameter
- Support `shared_memory_size` parameter
- Support `tmpfs` parameter
- Support `docker_volume_configuration` parameter
- Support target tracking scaling policy

## Changes
- Run containers referenced by `volumes_from` on hako oneshot
- Rename `additional_containers` parameter to `sidecars`
  - `additional_containers` is still supported for compatibility

## Bug fixes
- Show `--volumes-from` in dry-run output
- Fix `--init` not being shown in dry-run output

# 2.2.0 (2018-06-29)
## New features
- Add support for `scheduling_strategy` on service
- Change existing ELB's subnets when different from definition
## Bug fixes
- Take task-level cpu/memory into account on scale out
- Show `--memory-reservation` in the dry-run output

# 2.1.0 (2018-04-18)
## New features
- Support Network Load Balancer
  - See [examples/hello-internal-nlb.jsonnet](examples/hello-internal-nlb.jsonnet)
- Support `health_check_grace_period_seconds`
  - See [examples/hello-lb-v2.jsonnet](examples/hello-lb-v2.jsonnet)

# 2.0.4 (2018-02-26)
## Bug fixes
- Pass AWS region of ECS scheduler to other AWS clients (CloudWatch, ApplicationAutoScaling)
- Eliminate `--memory` parameter from dry-run output if it's not given
- Give missing unit to the value of `--memory` parameter in dry-run output
- Take `memory_reservation` into account when calculating required memory

# 2.0.3 (2018-02-16)
## Bug fixes
- create_aws_cloud_watch_logs_log_group script: Skip creating CloudWatch log group on dry-run

# 2.0.2 (2017-12-19)
## Bug fixes
- Skip expanding variables in `remove` and `stop`

# 2.0.1 (2017-12-14)
## Bug fixes
- Fix compatibility between Jsonnet and YAML when --dry-run is given

# 2.0.0 (2017-12-13)
## New features
- Support Jsonnet as the definition file format
    - See [docs/jsonnet.md](docs/jsonnet.md)
    - YAML definitions continues to be supported by hako at least v2.x series. Currently I don't have a plan which will be the default format.

# 1.9.0 (2017-12-06)
## New features
- Add support for awsvpc network mode
- Add support for Fargate
    - See [examples/hello-fargate.jsonnet](examples/hello-fargate.jsonnet) and [examples/hello-fargate-batch.jsonnet](examples/hello-fargate-batch.jsonnet)

# 1.8.4 (2017-11-24)
## Improvements
- Support `linux_parameters` option
- S3 and SNS client now uses the same region with ECS

# 1.8.3 (2017-09-25)
## Improvements
- Support `extra_hosts` option

# 1.8.2 (2017-09-15)
## Bug fixes
- Retry DeleteTargetGroup in `hako remove`
    - Deleting a load balancer may take several seconds
## Improvements
- Add target_group_attributes option to elb_v2

# 1.8.1 (2017-09-15)
## Improvements
- Add container_name and container_port option to elb and elb_v2
    - See [examples/hello-nofront.jsonnet](examples/hello-nofront.jsonnet)

# 1.8.0 (2017-09-15)
## Changes
- Migrate to aws-sdk v3

# 1.7.0 (2017-08-29)
## New features
- Add experimental `autoscaling_topic_for_oneshot` option to ECS scheduler
    - It publishes scale-out request to SNS topic.
    - Administrators is expected to receive SNS event and initiate scale-out.

# 1.6.2 (2017-07-11)
## Bug fixes
- Exclude unusable instances when checking remaining capacity

# 1.6.1 (2017-06-26)
## Changes
- Output cluster information in `--no-wait` mode

# 1.6.0 (2017-06-23)
## New features
- Add experimental option `--no-wait` to oneshot
    - `hako oneshot --no-wait` runs Docker container in background and return an identifier depending on scheduler.
    - In ECS scheduler, it will output the task's ARN.

# 1.5.2 (2017-06-08)
## Bug fixes
- Retry RegisterTaskDefinition when "too many concurrent attempts" error occurs

# 1.5.1 (2017-06-06)
## Bug fixes
- Fix error in dry-run mode when ALB isn't created yet

# 1.5.0 (2017-06-05)
## New features
- Support `load_balancer_attributes` option in elb_v2

# 1.4.0 (2017-05-25)
## New features
- Support `ulimits` option

# 1.3.3 (2017-05-23)
## Bug fixes
- Fix error of autoscaling for oneshot when container instances are empty
- Fix error when new task definition is registered
    - Regression in v1.3.2

# 1.3.2 (2017-05-23)
## Bug fixes
- Pass placement_configurations in oneshot mode
- Symbolize port_mapping keys to compare definitions correctly

## Improvements
- Reduce the number of DescribeTaskDefinition calls

# 1.3.1 (2017-05-16)
## Bug fixes
- Retry DescribeAutoScalingGroups when rate limited

# 1.3.0 (2017-05-15)
## New features
- Add `oneshot_notification_prefix` option
    - This is **experimental** , so might be reverted in near version.
    - This option enables S3 polling instead of ECS polling.

# 1.2.1 (2017-05-11)
## Bug fixes
- Retry DescribeTasks when rate limited

# 1.2.0 (2017-04-14)
## Changes
- Fail deployment when some tasks are stopped during deployment
    - It should prevent infinite loop when the new revision always fails to start

# 1.1.0 (2017-03-09)
## New features
- Add script hooks to rollback
    - `Script#rollback_starting`
        - Similar to deploy_starting, but without containers
    - `Script#rollback_started`
        - Current running image tag and target image tag are passed
    - `Script#rollback_finished`
        - Similar to deploy_finished, but without containers

# 1.0.1 (2017-03-07)
## Bug fixes
- Fix default value of `@volumes`
    - When `mount_points` is specified but no `volumes` is given, hako was raising unfriendly errors

# 1.0.0 (2017-03-06)
## Incompatibilities
- Raise error when env value is not String (#31)
