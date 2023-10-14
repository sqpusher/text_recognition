terraform {
  required_version = ">= 0.12"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "text_recognizer_lambda_policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = ["lambda:InvokeFunction"],
        Resource = [aws_lambda_function.recognizer_lambda_function.arn],
        Effect = "Allow"
      },
      {
        Action = ["apigateway:POST"],
        Resource = ["arn:aws:apigateway:${var.region}::/restapis/${aws_api_gateway_rest_api.lambda_api.id}/stages/dev/POST/text_recognizer"],
        Effect = "Allow"
      },
      {
        Action   = "textract:DetectDocumentText",
        Resource = "*",
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "lambda_policy_attachment" {
  name       = "policy-attachment"
  policy_arn = aws_iam_policy.lambda_policy.arn
  roles      = [aws_iam_role.lambda_role.name]
}

data "archive_file" "lambda_zip" {
  type = "zip"
  source_dir = "../src"
  output_path = "text_recognizer_lambda.zip"
}

resource "aws_lambda_function" "recognizer_lambda_function" {
  function_name = "lambdaTextRecognizer"
  filename      = "text_recognizer_lambda.zip"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role          = aws_iam_role.lambda_role.arn
  runtime       = "python3.9"
  handler       = "app.lambda_handler"
  timeout       = 10
}

resource "aws_lambda_permission" "lambda_api_permission" {
    statement_id  = "AllowAPIGatewayInvoke"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.recognizer_lambda_function.function_name
    principal     = "apigateway.amazonaws.com"
    source_arn    = "arn:aws:execute-api:${var.region}:${var
    .account_id}:${aws_api_gateway_rest_api.lambda_api.id}/*/*/*"
}


# Create AWS Gateway API configuration
resource "aws_api_gateway_rest_api" "lambda_api" {
  name = "lambda_api"
}

resource "aws_api_gateway_resource" "lambda_api_resource" {
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  parent_id   = aws_api_gateway_rest_api.lambda_api.root_resource_id
  path_part   = "text_recognizer"
}

resource "aws_api_gateway_method" "lambda_api_method" {
  rest_api_id   = aws_api_gateway_rest_api.lambda_api.id
  resource_id   = aws_api_gateway_resource.lambda_api_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "api_gateway_integration" {
  rest_api_id             = aws_api_gateway_rest_api.lambda_api.id
  resource_id             = aws_api_gateway_resource.lambda_api_resource.id
  http_method             = aws_api_gateway_method.lambda_api_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"

  uri = aws_lambda_function.recognizer_lambda_function.invoke_arn
}

resource "aws_api_gateway_deployment" "lambda_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.api_gateway_integration
  ]
  rest_api_id = aws_api_gateway_rest_api.lambda_api.id
  stage_name  = "dev"
}

output "api_gateway_invoke_url" {
  value = aws_api_gateway_deployment.lambda_api_deployment.invoke_url
}

output "lambda_function_arn" {
  value = aws_lambda_function.recognizer_lambda_function.arn
}