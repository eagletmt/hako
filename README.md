# Hako
[![Gem Version](https://badge.fury.io/rb/hako.svg)](http://badge.fury.io/rb/hako)
![CI](https://github.com/eagletmt/hako/workflows/CI/badge.svg)

Deploy Docker container.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'hako'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install hako

## Usage

```
% hako deploy examples/hello.jsonnet
I, [2015-10-02T12:51:24.530274 #7988]  INFO -- : Registered task-definition: arn:aws:ecs:ap-northeast-1:XXXXXXXXXXXX:task-definition/hello:29
I, [2015-10-02T12:51:24.750501 #7988]  INFO -- : Uploaded front configuration to s3://nanika/hako/front_config/hello.conf
I, [2015-10-02T12:51:24.877409 #7988]  INFO -- : Updated service: arn:aws:ecs:ap-northeast-1:XXXXXXXXXXXX:service/hello
I, [2015-10-02T12:56:07.284874 #7988]  INFO -- : Deployment completed

% hako deploy examples/hello.jsonnet
I, [2015-10-02T12:56:12.262760 #8141]  INFO -- : Deployment isn't needed

% hako status examples/hello.jsonnet
Load balancer:
  hako-hello-XXXXXXXXXX.ap-northeast-1.elb.amazonaws.com:80 -> front:80
Deployments:
  [PRIMARY] hello:30 desired_count=2, pending_count=0, running_count=2
Tasks:
  [RUNNING]: i-XXXXXXXX (ecs-001)
  [RUNNING]: i-YYYYYYYY (ecs-002)
Events:
  2015-10-05 13:35:53 +0900: (service hello) has reached a steady state.
  2015-10-05 13:35:14 +0900: (service hello) stopped 1 running tasks.

% hako rollback examples/hello.jsonnet
I, [2016-05-02T13:07:12.679926 #10961]  INFO -- : Current task defintion is hello:29. Rolling back to arn:aws:ecs:ap-northeast-1:XXXXXXXXXXXX:task-definition/hello:28
I, [2016-05-02T13:07:12.959116 #10961]  INFO -- : Updated service: arn:aws:ecs:ap-northeast-1:XXXXXXXXXXXX:service/hello
I, [2016-05-02T13:08:27.280686 #10961]  INFO -- : Deployment completed
```

Run oneshot command.

```
% hako oneshot examples/hello.jsonnet date
I, [2017-07-18T18:14:06.099763 #6627]  INFO -- : Task definition isn't changed: arn:aws:ecs:ap-northeast-1:XXXXXXXXXXXX:task-definition/hello-oneshot:32
I, [2017-07-18T18:14:06.147062 #6627]  INFO -- : Started task: arn:aws:ecs:ap-northeast-1:XXXXXXXXXXXX:task/01234567-89ab-cdef-0123-456789abcdef
I, [2017-07-18T18:14:06.193860 #6627]  INFO -- : Container instance is arn:aws:ecs:ap-northeast-1:XXXXXXXXXXXX:container-instance/01234567-89ab-cdef-0123-456789abcdef (i-0123456789abcdef0)
I, [2017-07-18T18:14:37.826389 #6627]  INFO -- : Started at 2017-07-18 18:14:37 +0900
I, [2017-07-18T18:14:37.826482 #6627]  INFO -- : Stopped at 2017-07-18 18:14:37 +0900 (reason: Essential container in task exited)
I, [2017-07-18T18:14:37.826520 #6627]  INFO -- : Oneshot task finished
I, [2017-07-18T18:14:37.826548 #6627]  INFO -- : app has stopped with exit_code=0
```

See also [docs/ecs-task-notification.md](docs/ecs-task-notification.md).

## Front image
The front container receives these environment variables.

- `S3_CONFIG_BUCKET` and `S3_CONFIG_KEY`
    - The front container should download configuration file from S3.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/eagletmt/hako.

