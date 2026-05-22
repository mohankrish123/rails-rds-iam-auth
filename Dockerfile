# Build stage - install system dependencies and gems
FROM ruby:3.1.2 AS build

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      curl unzip gnupg build-essential libpq-dev nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip" && \
    unzip /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/aws*

RUN gem install bundler

COPY Gemfile ./Gemfile
RUN bundle install

# Runtime stage
FROM ruby:3.1.2-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      libpq5 curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /usr/local/aws-cli /usr/local/aws-cli
COPY --from=build /usr/local/bin/aws /usr/local/bin/aws

RUN rails new . --database=postgresql --skip-bundle --force

COPY Gemfile ./Gemfile
RUN bundle install

COPY rds_iam_auth.rb config/initializers/rds_iam_auth.rb
COPY database.yml ./config/database.yml

EXPOSE 3000

CMD ["rails", "server", "-b", "0.0.0.0"]
