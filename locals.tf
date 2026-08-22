###############################################################################
# locals.tf — convención de nombres y valores derivados
###############################################################################
locals {
  name_prefix = "${var.project}-${var.env}"

  azs = ["${var.region}a", "${var.region}b"]

  # Subredes: 2 públicas (NAT) + 2 privadas (Fargate)
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.2.0/24", "10.0.4.0/24"]

  # Los 3 servicios de cómputo del sistema
  services = ["events-api", "events-delivery", "events-simulator"]

  tags = {
    Project     = var.project
    Environment = var.env
  }
}
