terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-2"
}

# --- variables ---

variable "repo_url" {
  description = "GitHub repository HTTPS URL"
  type        = string
}

# --- IAM role for CodeBuild ---

resource "aws_iam_role" "codebuild" {
  name = "codebuild-webhook-rename-repro"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# --- CodeBuild project ---

resource "aws_codebuild_project" "example" {
  name                 = "codebuild-webhook-rename-repro"
  service_role         = aws_iam_role.codebuild.arn
  project_visibility   = "PUBLIC_READ"
  resource_access_role = aws_iam_role.codebuild.arn
  badge_enabled        = true

  source {
    type      = "GITHUB"
    location  = var.repo_url
    buildspec = <<EOF
version: 0.2
phases:
  build:
    commands:
      - echo "hello from CodeBuild"
EOF
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }
}

# --- Webhook ---

resource "aws_codebuild_webhook" "example" {
  project_name = aws_codebuild_project.example.name

  lifecycle {
    # AWS/CodeBuild can keep reporting the webhook as present after GitHub
    # invalidates it during a repository rename. Recreate it with source changes.
    replace_triggered_by = [
      aws_codebuild_project.example.source[0].location,
    ]
  }
}

# --- Outputs ---

output "badge_url" {
  value = aws_codebuild_project.example.badge_url
}
