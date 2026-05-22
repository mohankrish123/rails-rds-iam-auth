# config/initializers/aws_rds_iam.rb

if Rails.env.production?
  puts("Generating AWS RDS IAM auth token...")

  PG::AWS_RDS_IAM.auth_token_generators.add :custom do
    PG::AWS_RDS_IAM::AuthTokenGenerator.new(
      region: ENV.fetch('AWS_REGION', 'ap-southeast-2'))
  end
end
