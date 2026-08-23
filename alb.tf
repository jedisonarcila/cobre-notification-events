# alb.tf — ALB interno entre el VPC Link y las tareas de events-api.
#
# Patron recomendado por AWS para exponer Fargate detras de un HTTP API:
#   API Gateway -> VPC Link -> ALB interno -> Target Group (8080) -> tareas
#
# Reemplaza la integracion previa via Cloud Map (que daba 503 por la
# resolucion SRV). El ALB da health checks HTTP reales y enrutamiento
# explicito al puerto 8080.

# ---------- Security group del ALB ----------
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-sg-alb"
  description = "ALB interno de events-api (ingreso desde VPC Link, egreso a tareas)"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name_prefix}-sg-alb" }
}

# El VPC Link (SG api) llega al ALB en 80.
resource "aws_vpc_security_group_ingress_rule" "alb_from_vpclink" {
  security_group_id            = aws_security_group.alb.id
  description                  = "HTTP 80 desde el VPC Link"
  referenced_security_group_id = aws_security_group.api.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

# El ALB sale hacia las tareas en 8080.
resource "aws_vpc_security_group_egress_rule" "alb_to_tasks" {
  security_group_id            = aws_security_group.alb.id
  description                  = "8080 hacia las tareas de events-api"
  referenced_security_group_id = aws_security_group.api.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

# La tarea (SG api) recibe 8080 desde el ALB.
resource "aws_vpc_security_group_ingress_rule" "api_from_alb" {
  security_group_id            = aws_security_group.api.id
  description                  = "8080 desde el ALB interno"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

# ---------- ALB interno ----------
resource "aws_lb" "api" {
  name               = "${local.name_prefix}-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.private[*].id
  tags               = { Name = "${local.name_prefix}-alb" }
}

# ---------- Target group (IP, porque Fargate/awsvpc) ----------
resource "aws_lb_target_group" "api" {
  name        = "${local.name_prefix}-tg-api"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/actuator/health"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
    # La app protege /actuator/health con Spring Security (responde 401 sin token).
    # Un 401 confirma que la app esta viva y respondiendo, suficiente para el health check.
    # Alternativa mas limpia: permitir /actuator/health sin auth en el SecurityConfig.
    matcher             = "200,401"
  }

  tags = { Name = "${local.name_prefix}-tg-api" }
}

# ---------- Listener HTTP 80 -> target group ----------
resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
