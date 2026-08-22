###############################################################################
# observability.tf — Alarmas + Managed Grafana
# (Los log groups de ECS se crean en ecs.tf, retención 7d.)
###############################################################################

# ---------- Alarmas SQS: profundidad de DLQ (mensajes atascados) ----------
resource "aws_cloudwatch_metric_alarm" "raw_dlq_depth" {
  alarm_name          = "${local.name_prefix}-raw-dlq-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Mensajes en la DLQ de raw-events"
  dimensions          = { QueueName = aws_sqs_queue.raw_events_dlq.name }
  tags                = { Name = "${local.name_prefix}-raw-dlq-depth" }
}

resource "aws_cloudwatch_metric_alarm" "deliveries_dlq_depth" {
  alarm_name          = "${local.name_prefix}-deliveries-dlq-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Mensajes en la DLQ de deliveries"
  dimensions          = { QueueName = aws_sqs_queue.deliveries_dlq.name }
  tags                = { Name = "${local.name_prefix}-deliveries-dlq-depth" }
}

# ---------- Alarma de antigüedad del mensaje más viejo en deliveries ----------
resource "aws_cloudwatch_metric_alarm" "deliveries_age" {
  alarm_name          = "${local.name_prefix}-deliveries-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 3600 # 1h: retraso anómalo en entregas
  alarm_description   = "Retraso en la entrega (mensaje más viejo en deliveries)"
  dimensions          = { QueueName = aws_sqs_queue.deliveries.name }
  tags                = { Name = "${local.name_prefix}-deliveries-age" }
}

# ---------- Managed Grafana (dashboards near-real-time sobre CloudWatch) ----------
data "aws_iam_policy_document" "grafana_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["grafana.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "grafana" {
  name               = "${local.name_prefix}-grafana"
  assume_role_policy = data.aws_iam_policy_document.grafana_assume.json
}

resource "aws_iam_role_policy_attachment" "grafana_cw" {
  role       = aws_iam_role.grafana.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_grafana_workspace" "main" {
  name                     = "${local.name_prefix}-grafana"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana.arn
  data_sources             = ["CLOUDWATCH"]
  tags                     = { Name = "${local.name_prefix}-grafana" }
}
