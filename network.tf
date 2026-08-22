###############################################################################
# network.tf — VPC, subredes (2 AZ), IGW, NAT, route tables,
#              VPC endpoints y Security Groups (cadena de menor privilegio)
###############################################################################

# ---------- VPC ----------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${local.name_prefix}-vpc" }
}

# ---------- Internet Gateway ----------
# Puerta de la VPC a internet. Rol real: EGRESO de los webhooks
# (Fargate privado -> NAT -> IGW -> internet). NO recibe la entrada de la API:
# API Gateway es gestionado y vive fuera de la VPC.
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

# ---------- Subredes públicas (alojan los NAT) ----------
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.name_prefix}-public-${local.azs[count.index]}" }
}

# ---------- Subredes privadas (alojan el Fargate, sin IP pública) ----------
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags              = { Name = "${local.name_prefix}-private-${local.azs[count.index]}" }
}

# ---------- NAT Gateways (uno por AZ, para HA del egreso) ----------
resource "aws_eip" "nat" {
  count  = 2
  domain = "vpc"
  tags   = { Name = "${local.name_prefix}-nat-eip-${count.index + 1}" }
}

resource "aws_nat_gateway" "nat" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${local.name_prefix}-nat-${local.azs[count.index]}" }
  depends_on    = [aws_internet_gateway.igw]
}

# ---------- Route tables ----------
# Pública: 0.0.0.0/0 -> IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${local.name_prefix}-rt-public" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Privada (una por AZ): 0.0.0.0/0 -> NAT de su misma AZ
resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index].id
  }
  tags = { Name = "${local.name_prefix}-rt-private-${local.azs[count.index]}" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ---------- VPC Endpoints ----------
# Gateway endpoints (S3, DynamoDB): gratis, se asocian por route table.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id
  tags              = { Name = "${local.name_prefix}-vpce-s3" }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id
  tags              = { Name = "${local.name_prefix}-vpce-dynamodb" }
}

# Interface endpoints (SQS, Secrets, ECR x2, CloudWatch Logs, STS):
# el tráfico AWS-interno NO sale por el NAT.
locals {
  interface_endpoints = {
    sqs     = "com.amazonaws.${var.region}.sqs"
    secrets = "com.amazonaws.${var.region}.secretsmanager"
    ecr_api = "com.amazonaws.${var.region}.ecr.api"
    ecr_dkr = "com.amazonaws.${var.region}.ecr.dkr"
    logs    = "com.amazonaws.${var.region}.logs"
    sts     = "com.amazonaws.${var.region}.sts"
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = local.interface_endpoints
  vpc_id              = aws_vpc.main.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
  tags                = { Name = "${local.name_prefix}-vpce-${each.key}" }
}

###############################################################################
# Security Groups — cadena de menor privilegio (se referencian por SG-origen)
###############################################################################

# SG-api: events-api. Recibe del VPC Link; sale a los endpoints (443).
resource "aws_security_group" "api" {
  name        = "${local.name_prefix}-sg-api"
  description = "events-api (recibe por VPC Link, sale a VPC endpoints)"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name_prefix}-sg-api" }
}

# SG-worker: events-delivery y events-simulator. Sin entrada.
# Sale a endpoints (443) y a 0.0.0.0/0 por NAT (webhooks del cliente).
resource "aws_security_group" "worker" {
  name        = "${local.name_prefix}-sg-worker"
  description = "workers (sin entrada; egreso a endpoints y a webhooks por NAT)"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name_prefix}-sg-worker" }
}

# SG-endpoints: Interface Endpoints. Reciben 443 de api y worker.
resource "aws_security_group" "endpoints" {
  name        = "${local.name_prefix}-sg-endpoints"
  description = "Interface endpoints (443 <- api, worker)"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name_prefix}-sg-endpoints" }
}

# --- Reglas SG-api ---
resource "aws_vpc_security_group_ingress_rule" "api_from_vpclink" {
  security_group_id = aws_security_group.api.id
  description       = "HTTP app desde VPC Link (rango de la VPC)"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "api_to_endpoints" {
  security_group_id            = aws_security_group.api.id
  description                  = "443 a interface endpoints"
  referenced_security_group_id = aws_security_group.endpoints.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

# --- Reglas SG-worker ---
resource "aws_vpc_security_group_egress_rule" "worker_to_endpoints" {
  security_group_id            = aws_security_group.worker.id
  description                  = "443 a interface endpoints (SQS/Secrets/...)"
  referenced_security_group_id = aws_security_group.endpoints.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "worker_to_internet" {
  security_group_id = aws_security_group.worker.id
  description       = "443 a 0.0.0.0/0 por NAT (entrega de webhooks del cliente)"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# --- Reglas SG-endpoints ---
resource "aws_vpc_security_group_ingress_rule" "endpoints_from_api" {
  security_group_id            = aws_security_group.endpoints.id
  description                  = "443 desde SG-api"
  referenced_security_group_id = aws_security_group.api.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_worker" {
  security_group_id            = aws_security_group.endpoints.id
  description                  = "443 desde SG-worker"
  referenced_security_group_id = aws_security_group.worker.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}
