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
