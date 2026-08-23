###############################################################################
# ecs.tf — Cluster + 3 servicios Fargate + ECR + autoscaling + Cloud Map
#
# DESPLIEGUE (Opción B): la task def referencia la imagen por tag inmutable
#   image = "<ecr>:${var.image_tag}"
# Flujo: mvn package -> docker build -> push a ECR con SHA -> apply -var image_tag=<sha>
#
# A FUTURO (Opción C, producción): que el pipeline actualice el service y
# Terraform ignore el task_definition -> descomentar lifecycle.ignore_changes.
###############################################################################

# ---------- ECR: un repo por servicio ----------
resource "aws_ecr_repository" "svc" {
  for_each             = toset(local.services)
  name                 = "${local.name_prefix}-${each.value}"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = { Name = "${local.name_prefix}-${each.value}" }
}

# ---------- Cluster ----------
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = { Name = "${local.name_prefix}-cluster" }
}

# ---------- CloudWatch Log Groups (uno por servicio, 7 días) ----------
resource "aws_cloudwatch_log_group" "svc" {
  for_each          = toset(local.services)
  name              = "/ecs/${local.name_prefix}/${each.value}"
  retention_in_days = 7
  tags              = { Name = "${local.name_prefix}-log-${each.value}" }
}

# ===================== events-api (recibe tráfico) =====================
resource "aws_ecs_task_definition" "api" {
  family                   = "${local.name_prefix}-events-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.task_api.arn

  container_definitions = jsonencode([{
    name      = "events-api"
<<<<<<< Updated upstream
    image     = "${aws_ecr_repository.svc["events-api"].repository_url}:${var.image_tag}"
=======
    image     = "${aws_ecr_repository.svc["events-api"].repository_url}:${var.image_tag_api}"
>>>>>>> Stashed changes
    essential = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    environment = [
      { name = "TABLE_EVENTS", value = aws_dynamodb_table.notification_events.name },
      { name = "TABLE_SUBS",   value = aws_dynamodb_table.subscriptions.name },
<<<<<<< Updated upstream
      { name = "QUEUE_DELIVERIES_URL", value = aws_sqs_queue.deliveries.url }
=======
      { name = "QUEUE_DELIVERIES_URL", value = aws_sqs_queue.deliveries.url },
      # Issuer de Cognito para que Spring Security (resource server) valide los JWT.
      { name = "COGNITO_ISSUER_URI", value = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}" },
      # Audience esperado en el token (el app client M2M).
      { name = "COGNITO_AUDIENCE", value = aws_cognito_user_pool_client.m2m.id },
      # DEBUG TEMPORAL — REVERTIR ANTES DE ENTREGAR.
      # Loguea el proceso de validacion del JWT (issuer, audience, JWKS) y el flujo web.
      { name = "LOGGING_LEVEL_ORG_SPRINGFRAMEWORK_SECURITY", value = "INFO" },
      { name = "LOGGING_LEVEL_ORG_SPRINGFRAMEWORK_WEB",      value = "INFO" }
>>>>>>> Stashed changes
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.svc["events-api"].name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "api"
      }
    }
  }])
  tags = { Name = "${local.name_prefix}-events-api" }
}

resource "aws_ecs_service" "api" {
  name            = "${local.name_prefix}-events-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.api.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "events-api"
    container_port   = 8080
  }

  # Espera a que el listener exista antes de crear el servicio.
  depends_on = [aws_lb_listener.api]

  # Despliegue rolling con drenaje (recibe tráfico).
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  force_new_deployment               = true

  # A FUTURO (pipeline despliega la imagen):
  # lifecycle { ignore_changes = [task_definition, desired_count] }

  tags = { Name = "${local.name_prefix}-events-api" }
}

# ===================== events-delivery (worker, sin tráfico) =====================
resource "aws_ecs_task_definition" "delivery" {
  family                   = "${local.name_prefix}-events-delivery"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.task_delivery.arn

  container_definitions = jsonencode([{
    name      = "events-delivery"
    image     = "${aws_ecr_repository.svc["events-delivery"].repository_url}:${var.image_tag}"
    essential = true
    environment = [
      { name = "QUEUE_RAW_URL",        value = aws_sqs_queue.raw_events.url },
      { name = "QUEUE_DELIVERIES_URL", value = aws_sqs_queue.deliveries.url },
      { name = "TABLE_EVENTS",         value = aws_dynamodb_table.notification_events.name },
      { name = "TABLE_SUBS",           value = aws_dynamodb_table.subscriptions.name }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.svc["events-delivery"].name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "delivery"
      }
    }
  }])
  tags = { Name = "${local.name_prefix}-events-delivery" }
}

resource "aws_ecs_service" "delivery" {
  name            = "${local.name_prefix}-events-delivery"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.delivery.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.worker.id]
    assign_public_ip = false
  }

  # Worker: no recibe tráfico, reemplazo más simple.
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  force_new_deployment               = true

  tags = { Name = "${local.name_prefix}-events-delivery" }
}

# ===================== events-simulator (andamiaje) =====================
resource "aws_ecs_task_definition" "simulator" {
  family                   = "${local.name_prefix}-events-simulator"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.task_simulator.arn

  container_definitions = jsonencode([{
    name      = "events-simulator"
    image     = "${aws_ecr_repository.svc["events-simulator"].repository_url}:${var.image_tag}"
    essential = true
    environment = [
      { name = "QUEUE_RAW_URL", value = aws_sqs_queue.raw_events.url }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.svc["events-simulator"].name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "sim"
      }
    }
  }])
  tags = { Name = "${local.name_prefix}-events-simulator" }
}

resource "aws_ecs_service" "simulator" {
  name            = "${local.name_prefix}-events-simulator"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.simulator.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.worker.id]
    assign_public_ip = false
  }

  tags = { Name = "${local.name_prefix}-events-simulator" }
}

# ---------- Autoscaling (api y delivery, por CPU) ----------
resource "aws_appautoscaling_target" "svc" {
  for_each           = { api = aws_ecs_service.api.name, delivery = aws_ecs_service.delivery.name }
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.main.name}/${each.value}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  for_each           = aws_appautoscaling_target.svc
  name               = "${local.name_prefix}-${each.key}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = each.value.resource_id
  scalable_dimension = each.value.scalable_dimension
  service_namespace  = each.value.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 65
  }
}
