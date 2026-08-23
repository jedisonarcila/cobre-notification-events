###############################################################################
# iam.tf — execution role (compartido) + task roles por servicio (menor priv.)
###############################################################################

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ---------- Execution role (jala imagen de ECR, escribe logs) ----------
resource "aws_iam_role" "ecs_execution" {
  name               = "${local.name_prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = { Name = "${local.name_prefix}-ecs-execution" }
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ================= Task role: events-api =================
resource "aws_iam_role" "task_api" {
  name               = "${local.name_prefix}-task-api"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = { Name = "${local.name_prefix}-task-api" }
}

data "aws_iam_policy_document" "task_api" {
  # Lee/consulta notification_events (+GSI) y subscriptions; CRUD subs.
  statement {
    sid = "DynamoApi"
    actions = ["dynamodb:Query", "dynamodb:GetItem", "dynamodb:PutItem",
    "dynamodb:UpdateItem", "dynamodb:DeleteItem"]
    resources = [
      aws_dynamodb_table.notification_events.arn,
      "${aws_dynamodb_table.notification_events.arn}/index/*",
      aws_dynamodb_table.subscriptions.arn
    ]
  }
  # Replay: reencola en deliveries.
  statement {
    sid       = "SqsReplay"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.deliveries.arn]
  }
  # Alta de HMAC al crear suscripción.
  statement {
    sid = "SecretsWrite"
    actions = ["secretsmanager:CreateSecret", "secretsmanager:PutSecretValue",
    "secretsmanager:DescribeSecret"]
    resources = ["arn:aws:secretsmanager:${var.region}:*:secret:cobre/webhook-hmac/*"]
  }
  # Cifrado en reposo de DynamoDB: las tablas usan una CMK, leer/escribir requiere KMS.
  statement {
    sid       = "DynamoKmsAccess"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.dynamodb.arn]
  }
}

resource "aws_iam_role_policy" "task_api" {
  name   = "${local.name_prefix}-task-api-policy"
  role   = aws_iam_role.task_api.id
  policy = data.aws_iam_policy_document.task_api.json
}

# ================= Task role: events-delivery =================
resource "aws_iam_role" "task_delivery" {
  name               = "${local.name_prefix}-task-delivery"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = { Name = "${local.name_prefix}-task-delivery" }
}

data "aws_iam_policy_document" "task_delivery" {
  # Consume raw-events, produce/consume deliveries.
  statement {
    sid = "SqsWork"
    actions = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:SendMessage",
    "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"]
    resources = [
      aws_sqs_queue.raw_events.arn,
      aws_sqs_queue.deliveries.arn
    ]
  }
  # Lee subscriptions (matching) y escribe el desenlace en notification_events.
  statement {
    sid = "Dynamo"
    actions = ["dynamodb:Query", "dynamodb:GetItem", "dynamodb:PutItem",
    "dynamodb:UpdateItem"]
    resources = [
      aws_dynamodb_table.subscriptions.arn,
      aws_dynamodb_table.notification_events.arn
    ]
  }
  # Resuelve el HMAC del cliente para firmar.
  statement {
    sid       = "SecretsRead"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${var.region}:*:secret:cobre/webhook-hmac/*"]
  }
  # Publica métricas a CloudWatch (Micrometer). PutMetricData no admite
  # restricción por recurso; se acota por namespace con una condición.
  statement {
    sid       = "CloudWatchMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["notification-events-delivery", "notification-events-api", "notification-events-simulator"]
    }
  }
  # Cifrado en reposo de DynamoDB: las tablas usan una CMK, así que leer/escribir
  # requiere descifrar (Decrypt) y generar claves de datos (GenerateDataKey).
  statement {
    sid       = "DynamoKmsAccess"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.dynamodb.arn]
  }
}

resource "aws_iam_role_policy" "task_delivery" {
  name   = "${local.name_prefix}-task-delivery-policy"
  role   = aws_iam_role.task_delivery.id
  policy = data.aws_iam_policy_document.task_delivery.json
}

# ================= Task role: events-simulator =================
resource "aws_iam_role" "task_simulator" {
  name               = "${local.name_prefix}-task-simulator"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = { Name = "${local.name_prefix}-task-simulator" }
}

data "aws_iam_policy_document" "task_simulator" {
  # Solo produce a raw-events.
  statement {
    sid       = "SqsProduce"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.raw_events.arn]
  }
}

resource "aws_iam_role_policy" "task_simulator" {
  name   = "${local.name_prefix}-task-simulator-policy"
  role   = aws_iam_role.task_simulator.id
  policy = data.aws_iam_policy_document.task_simulator.json
}
