###############################################################################
# dynamodb.tf — notification_events (+GSI +Streams) y subscriptions
###############################################################################

# ---------- notification_events ----------
# Registro del desenlace + read model de la API.
# PK=client_id, SK=delivery_date#notification_event_id
# GSI por delivery_status: PK=client_id#delivery_status, SK=delivery_date
resource "aws_dynamodb_table" "notification_events" {
  name         = "${local.name_prefix}-notification-events"
  billing_mode = "PAY_PER_REQUEST" # on-demand: escala a cero
  hash_key     = "client_id"
  range_key    = "sk"

  attribute {
    name = "client_id"
    type = "S"
  }
  attribute {
    name = "sk" # delivery_date#notification_event_id
    type = "S"
  }
  attribute {
    name = "gsi1_pk" # client_id#delivery_status
    type = "S"
  }
  attribute {
    name = "gsi1_sk" # delivery_date
    type = "S"
  }

  global_secondary_index {
    name            = "gsi-status"
    hash_key        = "gsi1_pk"
    range_key       = "gsi1_sk"
    projection_type = "INCLUDE"
    non_key_attributes = [
      "event_type", "delivery_status", "webhook_url", "attempt_count"
    ]
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true # borra a los 90 días (caliente)
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES" # alimenta el archivado

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = "${local.name_prefix}-notification-events" }
}

# ---------- subscriptions ----------
# Configuración de enrutamiento (cliente–event_type–URL).
# PK=client_id, SK=event_type#subscription_id
resource "aws_dynamodb_table" "subscriptions" {
  name         = "${local.name_prefix}-subscriptions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "client_id"
  range_key    = "sk"

  attribute {
    name = "client_id"
    type = "S"
  }
  attribute {
    name = "sk" # event_type#subscription_id
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = "${local.name_prefix}-subscriptions" }
}
