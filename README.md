# Hako

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/hako`. To experiment with that code, run `bin/console` for an interactive prompt.

TODO: Delete this and the text above, and describe your gem

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
% hako deploy examples/hello.yml
I, [2015-10-02T12:51:24.530274 #7988]  INFO -- : Registered task-definition: arn:aws:ecs:ap-northeast-1:XXXXXXXXXXXX:task-definition/hello:29
I, [2015-10-02T12:51:24.750501 #7988]  INFO -- : Uploaded front configuration to s3://nanika/hako/front_config/hello.conf
I, [2015-10-02T12:51:24.877409 #7988]  INFO -- : Updated service: arn:aws:ecs:ap-northeast-1:XXXXXXXXXXXX:service/hello
I, [2015-10-02T12:56:07.284874 #7988]  INFO -- : Deployment completed

% hako deploy examples/hello.yml
I, [2015-10-02T12:56:12.262760 #8141]  INFO -- : Deployment isn't needed

% hako status examples/hello.yml
Load balancer:
  hako-hello-XXXXXXXXXX.ap-northeast-1.elb.amazonaws.com:80 -> front:80
Deployments:
  [PRIMARY] desired_count=2, pending_count=0, running_count=2
Tasks:
  [RUNNING]: i-XXXXXXXX (ecs-001)
  [RUNNING]: i-YYYYYYYY (ecs-002)
Events:
  2015-10-05 13:35:53 +0900: (service hello) has reached a steady state.
  2015-10-05 13:35:14 +0900: (service hello) stopped 1 running tasks.

```

## Front image
The front container receives these environment variables.

- `S3_CONFIG_BUCKET` and `S3_CONFIG_KEY`
    - The front container should download configuration file from S3.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/hako.

