###############################################################################
# cognito.tf — User Pool + Resource Server (scopes) + App Client M2M
###############################################################################
resource "aws_cognito_user_pool" "main" {
  name = "${local.name_prefix}-pool"
  tags = { Name = "${local.name_prefix}-pool" }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${local.name_prefix}-auth"
  user_pool_id = aws_cognito_user_pool.main.id
}

# Resource server: define los scopes que el token M2M puede pedir.
resource "aws_cognito_resource_server" "api" {
  identifier   = "https://api.cobre-notifications"
  name         = "${local.name_prefix}-api"
  user_pool_id = aws_cognito_user_pool.main.id

  scope {
    scope_name        = "notifications.read"
    scope_description = "Consultar notification_events"
  }
  scope {
    scope_name        = "notifications.replay"
    scope_description = "Reejecutar entregas fallidas"
  }
  scope {
    scope_name        = "subscriptions.write"
    scope_description = "CRUD de suscripciones"
  }
}

# App client M2M: client_credentials (sin login humano).
resource "aws_cognito_user_pool_client" "m2m" {
  name         = "${local.name_prefix}-m2m"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret                      = true
  allowed_oauth_flows                  = ["client_credentials"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes = [
    "https://api.cobre-notifications/notifications.read",
    "https://api.cobre-notifications/notifications.replay",
    "https://api.cobre-notifications/subscriptions.write"
  ]

  depends_on = [aws_cognito_resource_server.api]
}
