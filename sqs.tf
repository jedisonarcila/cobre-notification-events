###############################################################################
# sqs.tf — 2 colas + 2 DLQs + redrive (recursos planos, valores a mano)
#
# NOTA IMPORTANTE (para el panel):
#  - El backoff exponencial + jitter de los reintentos de ENTREGA NO se
#    configura aquí. Lo ejecuta el worker por mensaje con ChangeMessageVisibility
#    (código Java, Tarea 2). El attempt_count viaja en el mensaje y el worker
#    corta a los 6 intentos.
#  - Por eso el maxReceiveCount de la DLQ es una RED DE SEGURIDAD (fallos de
#    infraestructura), NO el mecanismo de los 6 reintentos.
###############################################################################

# ===================== raw-events =====================
resource "aws_sqs_queue" "raw_events_dlq" {
  name                      = "${local.name_prefix}-raw-events-dlq"
  message_retention_seconds = 1209600 # 14 días
  tags                      = { Name = "${local.name_prefix}-raw-events-dlq" }
}

resource "aws_sqs_queue" "raw_events" {
  name                       = "${local.name_prefix}-raw-events"
  visibility_timeout_seconds = 60     # tiempo para resolver matching + fan-out
  message_retention_seconds  = 345600 # 4 días
  receive_wait_time_seconds  = 10     # long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.raw_events_dlq.arn
    maxReceiveCount     = 5 # red de seguridad ante fallos de matching
  })

  tags = { Name = "${local.name_prefix}-raw-events" }
}

# ===================== deliveries =====================
resource "aws_sqs_queue" "deliveries_dlq" {
  name                      = "${local.name_prefix}-deliveries-dlq"
  message_retention_seconds = 1209600 # 14 días
  tags                      = { Name = "${local.name_prefix}-deliveries-dlq" }
}

resource "aws_sqs_queue" "deliveries" {
  name = "${local.name_prefix}-deliveries"
  # Visibilidad BASE. El worker la sobrescribe por mensaje (ChangeMessageVisibility)
  # con el backoff+jitter (~30s/1m/2m/4m/8m/16m). Límite SQS = 12h; cabe la ventana.
  visibility_timeout_seconds = 60
  message_retention_seconds  = 1209600 # 14 días (cubre la ventana de reintentos)
  receive_wait_time_seconds  = 10

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.deliveries_dlq.arn
    # Red de seguridad de INFRA (no los 6 reintentos, que los controla el worker).
    maxReceiveCount = 10
  })

  tags = { Name = "${local.name_prefix}-deliveries" }
}
