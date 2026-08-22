###############################################################################
# kms.tf — CMKs para cifrado en reposo (DynamoDB, S3, SQS, Secrets)
###############################################################################
resource "aws_kms_key" "dynamodb" {
  description             = "${local.name_prefix} CMK DynamoDB"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = { Name = "${local.name_prefix}-kms-dynamodb" }
}

resource "aws_kms_alias" "dynamodb" {
  name          = "alias/${local.name_prefix}-dynamodb"
  target_key_id = aws_kms_key.dynamodb.key_id
}

resource "aws_kms_key" "s3" {
  description             = "${local.name_prefix} CMK S3"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = { Name = "${local.name_prefix}-kms-s3" }
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${local.name_prefix}-s3"
  target_key_id = aws_kms_key.s3.key_id
}

resource "aws_kms_key" "secrets" {
  description             = "${local.name_prefix} CMK Secrets Manager"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = { Name = "${local.name_prefix}-kms-secrets" }
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${local.name_prefix}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}
