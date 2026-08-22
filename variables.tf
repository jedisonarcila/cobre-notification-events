###############################################################################
# variables.tf — entradas mínimas (el resto de valores va hardcoded en su .tf)
###############################################################################
variable "region" {
  description = "Región AWS"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefijo de nombres"
  type        = string
  default     = "cobre-notif"
}

variable "env" {
  description = "Entorno lógico (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# Opción B de despliegue: tag inmutable de la imagen por servicio.
# default 'latest' para aplicar sin pipeline; en serio usar el SHA del commit.
variable "image_tag" {
  description = "Tag de las imágenes en ECR a desplegar"
  type        = string
  default     = "latest"
}
