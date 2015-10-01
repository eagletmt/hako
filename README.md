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
% hako apply examples/hello.yml
I, [2015-10-01T15:39:53.661218 #20990]  INFO -- : Registered task-definition: arn:aws:ecs:ap-northeast-1:XXXXXXXXXXXX:task-definition/hello:18
I, [2015-10-01T15:39:53.799979 #20990]  INFO -- : Updated service: arn:aws:ecs:ap-northeast-1:XXXXXXXXXXXX:service/hello
I, [2015-10-01T15:42:42.013796 #20990]  INFO -- : Deployment completed
% hako apply examples/hello.yml
I, [2015-10-01T15:43:39.736100 #21117]  INFO -- : Deployment isn't needed
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/hako.

