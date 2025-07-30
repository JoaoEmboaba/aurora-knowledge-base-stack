provider "aws" {
  region = "us-east-1"
}

resource "aws_rds_cluster" "aurora-knowledge-base" {
  cluster_identifier           = "aurora-knowledge-base"
  engine                       = "aurora-postgresql"
  engine_mode                  = "provisioned"
  engine_version               = "16.6"
  database_name                = "postgres"
  master_username              = "postgres"
  vpc_security_group_ids       = ["sg-079b7bb0d993649d5"]
  manage_master_user_password  = true
  storage_encrypted            = true
  apply_immediately            = true
  skip_final_snapshot          = true
  enable_http_endpoint         = true
  deletion_protection          = false
  performance_insights_enabled = false
  port                         = 5432
  backup_retention_period      = 1

  serverlessv2_scaling_configuration {
    max_capacity             = 10.0
    min_capacity             = 0.5
    seconds_until_auto_pause = 1200
  }
}

resource "aws_rds_cluster_instance" "aurora-knowledge-base-cluster-instance" {
  cluster_identifier  = aws_rds_cluster.aurora-knowledge-base.id
  identifier          = "aurora-knowledge-base-instance"
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.aurora-knowledge-base.engine
  engine_version      = aws_rds_cluster.aurora-knowledge-base.engine_version
  publicly_accessible = true
}

resource "aws_sns_topic" "aurora-knowledge-base-topic" {
  name = "aurora-knowledge-base-topic"
}

resource "aws_db_event_subscription" "aurora-knowledge-base-event-subscription" {
  name      = "aurora-knowledge-base-event-subscription"
  sns_topic = aws_sns_topic.aurora-knowledge-base-topic.arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "init_knowledge_base" {
  function_name = "init-knowledge-base"
  runtime       = "python3.11"
  handler       = "lambda.handler"
  role          = aws_iam_role.lambda_exec_role.arn
  filename      = data.archive_file.lambda_zip.output_path
  timeout       = 30
  environment {
    variables = {
      DB_SECRET_ARN  = aws_rds_cluster.aurora-knowledge-base.master_user_secret[0].secret_arn
      DB_CLUSTER_ARN = aws_rds_cluster.aurora-knowledge-base.arn
    }
  }
  depends_on = [data.archive_file.lambda_zip]
}

resource "aws_lambda_permission" "allow_sns_invoke" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.init_knowledge_base.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.aurora-knowledge-base-topic.arn
}

resource "aws_sns_topic_subscription" "sns_lambda_subscription" {
  topic_arn = aws_sns_topic.aurora-knowledge-base-topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.init_knowledge_base.arn
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-policy"
  role = aws_iam_role.lambda_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "rds-data:ExecuteStatement",
          "rds-data:BatchExecuteStatement",
          "secretsmanager:GetSecretValue"
        ]
        Resource = "*"
        Effect   = "Allow"
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
        Effect   = "Allow"
      }
    ]
  })
}