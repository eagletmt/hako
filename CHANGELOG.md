# 1.0.1 (2017-03-07)
## Bug fixes
- Fix default value of `@volumes`
    - When `mount_points` is specified but no `volumes` is given, hako was raising unfriendly errors

# 1.0.0 (2017-03-06)
## Incompatibilities
- Raise error when env value is not String (#31)
