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
