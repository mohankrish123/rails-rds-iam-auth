# Rails with RDS IAM Authentication

A Rails 7 application configured to authenticate to Amazon RDS PostgreSQL using IAM database authentication instead of static passwords.

## Why IAM authentication over static passwords?

Static database credentials create operational burden:
- Secrets need rotating, and rotation failures cause outages
- Credentials stored in Secrets Manager or environment variables can leak through logs, error pages, or debugging sessions
- Every application copy holds a long-lived password, widening the blast radius of a compromise

IAM database authentication solves this by generating short-lived tokens (15-minute TTL) from the application's existing AWS identity. If the application already has an IAM role (via ECS task role, EC2 instance profile, or IRSA), it already has what it needs to connect to the database. No separate secret to manage, rotate, or protect.

## How it works

```
AWS IAM Role (task role / instance profile / IRSA)
        |
        v
pg-aws_rds_iam gem generates a 15-min auth token
        |
        v
Token used as the PostgreSQL password in database.yml
        |
        v
RDS validates the token against IAM policy
```

The [`pg-aws_rds_iam`](https://github.com/haines/pg-aws_rds_iam) gem hooks into the `pg` connection lifecycle. When Rails opens a database connection, the gem intercepts the password field and replaces it with a fresh IAM auth token. This is transparent to the rest of the application.

### Key files

| File | Purpose |
|---|---|
| `rds_iam_auth.rb` | Rails initialiser - registers a custom auth token generator using the application's AWS credentials |
| `database.yml` | Configures the `production` environment to use `aws_rds_iam_auth_token_generator: custom` instead of a static password |
| `Gemfile` | Includes `pg-aws_rds_iam` gem in the `:production` group |
| `Dockerfile` | Multi-stage build with AWS CLI and all gems pre-installed |

### database.yml: local vs RDS

The `development` environment connects to a local PostgreSQL container with static credentials. The `production` environment connects to RDS with IAM authentication and enforces SSL:

```yaml
production:
  <<: *default
  database: <%= ENV.fetch("DB_DATABASE", "postgres") %>
  username: <%= ENV.fetch("DB_USERNAME", "rails") %>
  host: <%= ENV.fetch("DB_HOST", "postgres") %>
  sslmode: require
  aws_rds_iam_auth_token_generator: custom
```

The `password` field is intentionally omitted in the `production` block. The gem generates a token on each connection attempt.

### rds_iam_auth.rb: the initialiser

The initialiser only activates in the `production` environment. It uses the AWS SDK's default credential chain — which automatically resolves credentials from ECS task roles, IRSA, EC2 instance profiles, or environment variables — and registers a token generator:

```ruby
if Rails.env.production?
  PG::AWS_RDS_IAM.auth_token_generators.add :custom do
    PG::AWS_RDS_IAM::AuthTokenGenerator.new(
      region: ENV.fetch('AWS_REGION', 'ap-southeast-2'))
  end
end
```

The `:custom` name matches the `aws_rds_iam_auth_token_generator: custom` value in `database.yml`.

## Prerequisites

### AWS side
- RDS PostgreSQL instance with IAM database authentication enabled
- IAM policy allowing `rds-db:connect` for the database user
- A database user created with `GRANT rds_iam TO <username>` (IAM users cannot use password auth)

### Local development
- Docker and Docker Compose

## Running locally

Local development uses the PostgreSQL container with static credentials (no AWS setup needed):

```bash
RAILS_ENV=development docker compose up --build
```

The Rails app will be available at `http://localhost:3000`.

## Running against RDS

To connect to a real RDS instance with IAM authentication:

```bash
export DB_HOST=<your-rds-endpoint>
export DB_USERNAME=<your-iam-db-user>
export DB_DATABASE=<your-database-name>
export AWS_REGION=ap-southeast-2

docker compose up --build
```

The AWS SDK's default credential chain automatically resolves credentials from the ECS task role, IRSA, or instance profile — no explicit AWS credential variables needed.

## Design decisions

### Why `pg-aws_rds_iam` instead of generating tokens manually?

The gem integrates with ActiveRecord's connection pool lifecycle. Tokens expire after 15 minutes, and the gem generates a fresh one on each new connection. Doing this manually would require hooking into connection checkout events and handling token refresh — the gem handles all of this.

### Why multi-stage Docker build?

The build stage installs compilers and development headers needed to build native gems (like `pg`). The runtime stage uses `ruby:slim` with only the compiled gems and runtime libraries. This reduces the final image size and removes build tools from the production container.

### Why include AWS CLI in the image?

Useful for debugging connectivity and IAM issues in the container: `aws sts get-caller-identity` to verify the role, `aws rds generate-db-auth-token` to manually test token generation. Not strictly required for the application itself.

## Other content

The `ruby-basics/` directory contains standalone Ruby language notes and is unrelated to this Rails application.
