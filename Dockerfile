# Base image
FROM ruby:3.1.2 AS base
USER root
WORKDIR /app
RUN apt update && apt install curl unzip net-tools gnupg jq htop wget git vim groff less -y
# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "/tmp/awscliv2.zip" && \
    unzip /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update && \
    rm -rf /tmp/aws* && \
    aws --version

# Install Node
FROM base AS node
USER root
WORKDIR /app
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
ENV NODE_MAJOR=16
RUN echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
    apt update && \
    apt install -y nodejs && \
    npm install --global yarn

FROM python:3.11-slim as awscli-installer

# # Install Rails
FROM base AS rails
USER root
WORKDIR /app
COPY --from=node /usr/bin/node /usr/bin/node
COPY --from=node /usr/lib/node_modules /usr/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/bin/npm
RUN ln -s ../lib/node_modules/yarn/bin/yarn /usr/bin/yarn
COPY --from=node /usr/bin/yarn /usr/bin/yarn

#Installing required gems
RUN gem install bundler webpacker

RUN rails new . --database=postgresql --skip-bundle

COPY Gemfile ./Gemfile

RUN bundle install

# Creating a new environment `release`
RUN cp config/environments/development.rb config/environments/release.rb

# Initialiser for rails rds iam authentication
COPY rds_iam_auth.rb config/initializers/rds_iam_auth.rb

COPY database.yml ./config/database.yml