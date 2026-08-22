###############################################################################
# archive.tf — TTL 90d -> DynamoDB Streams -> Firehose -> S3 (Parquet) -> Athena
###############################################################################

# ---------- Bucket de archivo ----------
resource "aws_s3_bucket" "archive" {
  bucket = "${local.name_prefix}-archive"
  tags   = { Name = "${local.name_prefix}-archive" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "archive" {
  bucket                  = aws_s3_bucket.archive.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Retención: 1 año por defecto (PARAMETRIZABLE en prod; compliance fintech
# suele exigir 5-7 años). Standard-IA -> Glacier -> expira.
resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id
  rule {
    id     = "archive-tiering"
    status = "Enabled"
    filter {}
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    expiration {
      days = 365
    }
  }
}

# ---------- Firehose (Streams -> S3 Parquet) ----------
data "aws_iam_policy_document" "firehose_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose" {
  name               = "${local.name_prefix}-firehose"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume.json
}

data "aws_iam_policy_document" "firehose" {
  statement {
    actions   = ["s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"]
    resources = [aws_s3_bucket.archive.arn, "${aws_s3_bucket.archive.arn}/*"]
  }
  statement {
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [aws_kms_key.s3.arn]
  }
}

resource "aws_iam_role_policy" "firehose" {
  name   = "${local.name_prefix}-firehose-policy"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose.json
}

resource "aws_kinesis_firehose_delivery_stream" "archive" {
  name        = "${local.name_prefix}-archive"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose.arn
    bucket_arn          = aws_s3_bucket.archive.arn
    prefix              = "events/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/"
    buffering_size      = 64
    buffering_interval  = 300
    compression_format  = "GZIP"
  }
  tags = { Name = "${local.name_prefix}-archive" }
}

# ---------- Glue + Athena (consulta del histórico) ----------
resource "aws_glue_catalog_database" "archive" {
  name = replace("${local.name_prefix}_archive", "-", "_")
}

resource "aws_athena_workgroup" "archive" {
  name = "${local.name_prefix}-wg"
  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.archive.bucket}/athena-results/"
    }
  }
  tags = { Name = "${local.name_prefix}-wg" }
}

# NOTA: DynamoDB Streams ya está habilitado en la tabla (dynamodb.tf).
# El puente Streams -> Firehose se hace con una Lambda de reenvío (código,
# fuera de este alcance de IaC base) o EventBridge Pipes. Se deja anotado.
