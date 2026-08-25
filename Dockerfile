FROM ruby:2.5

WORKDIR /usr/src/app
COPY . .
RUN bin/setup
RUN bundle exec rake install

ENTRYPOINT [ "/usr/local/bundle/bin/hako" ]