###############################################################################
# secrets.tf — Secrets Manager (HMAC por cliente)
#
# Convención: cobre/webhook-hmac/{client_id}. El secret_ref es DERIVABLE del
# client_id (no se guarda en la tabla de suscripciones).
# Aquí dejamos UN secreto de ejemplo/semilla; en operación se crea uno por
# cliente vía la app o un proceso de alta.
###############################################################################
resource "aws_secretsmanager_secret" "webhook_hmac_example" {
  name        = "cobre/webhook-hmac/example-client"
  description = "HMAC de ejemplo (patrón cobre/webhook-hmac/{client_id})"
  kms_key_id  = aws_kms_key.secrets.arn
  tags        = { Name = "${local.name_prefix}-hmac-example" }
}

# El valor se inyecta fuera de Terraform (no se versiona el secreto en el repo).
