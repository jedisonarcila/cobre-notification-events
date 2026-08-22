###############################################################################
# edge.tf — API Gateway (HTTP API) + JWT authorizer (Cognito) + VPC Link + WAF
#
# HTTP API (no REST): más barata, JWT authorizer nativo, VPC Link a Cloud Map
# SIN NLB. Si se necesitaran API keys / usage plans por cliente -> pasar a REST
# API y añadir un NLB delante del events-api.
###############################################################################

resource "aws_apigatewayv2_api" "http" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"
  tags          = { Name = "${local.name_prefix}-api" }
}

# ---------- JWT authorizer (valida el token de Cognito en el borde) ----------
resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = aws_apigatewayv2_api.http.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${local.name_prefix}-jwt"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.m2m.id]
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
  }
}

# ---------- VPC Link -> Cloud Map (events-api en subred privada) ----------
resource "aws_apigatewayv2_vpc_link" "main" {
  name               = "${local.name_prefix}-vpclink"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.api.id]
  tags               = { Name = "${local.name_prefix}-vpclink" }
}

resource "aws_apigatewayv2_integration" "api" {
  api_id             = aws_apigatewayv2_api.http.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.main.id
  integration_uri    = aws_service_discovery_service.api.arn
}

# ---------- Rutas (los 3 endpoints + CRUD suscripciones), todas con JWT ----------
locals {
  routes = [
    "GET /notification_events",
    "GET /notification_events/{id_notification}",
    "POST /notification_events/{id_notification}/replay",
    "GET /subscriptions",
    "POST /subscriptions",
    "PUT /subscriptions/{subscription_id}",
    "DELETE /subscriptions/{subscription_id}"
  ]
}

resource "aws_apigatewayv2_route" "routes" {
  for_each           = toset(local.routes)
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.api.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 500
    throttling_rate_limit  = 1000
  }
  tags = { Name = "${local.name_prefix}-stage" }
}

# ---------- WAF (WebACL con regla rate-based) ----------
resource "aws_wafv2_web_acl" "api" {
  name  = "${local.name_prefix}-waf"
  scope = "REGIONAL"
  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit"
    priority = 1
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-waf"
    sampled_requests_enabled   = true
  }
  tags = { Name = "${local.name_prefix}-waf" }
}

resource "aws_wafv2_web_acl_association" "api" {
  resource_arn = aws_apigatewayv2_stage.default.arn
  web_acl_arn  = aws_wafv2_web_acl.api.arn
}
