# config/initializers/aws_rds_iam.rb

if Rails.env.release?
  puts("Generating AWS RDS IAM auth token...")

  cred = Aws::Credentials.new(
    ENV.fetch('AWS_ACCESS_KEY_ID'),
    ENV.fetch('AWS_SECRET_ACCESS_KEY'),
    ENV['AWS_SESSION_TOKEN']
  )

  PG::AWS_RDS_IAM.auth_token_generators.add :custom do
    PG::AWS_RDS_IAM::AuthTokenGenerator.new(
        credentials: cred,
        region: ENV['AWS_REGION'])
  end
end
