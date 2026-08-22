# Cobre — Notifications · Infraestructura (Terraform)

IaC del sistema de entrega de notificaciones vía webhook + API self-service,
sobre AWS (ECS/Fargate, event-driven). Reto técnico Sr Software Engineer.

## Requisitos
- Terraform >= 1.6
- AWS CLI configurado (credenciales con permisos de administración para el reto)
- Docker (para construir y publicar las imágenes de los servicios)

## Estructura (recursos planos, sin módulos)
| Archivo | Contenido |
|---|---|
| `providers.tf` | Terraform + provider AWS (state local) |
| `variables.tf` / `locals.tf` / `outputs.tf` / `terraform.tfvars` | Entradas, nombres, salidas |
| `network.tf` | VPC, 2 AZ, subredes, IGW, NAT, route tables, VPC endpoints, Security Groups |
| `edge.tf` | API Gateway (HTTP API) + JWT authorizer (Cognito) + VPC Link + WAF |
| `cognito.tf` | User pool + resource server (scopes) + app client M2M |
| `ecs.tf` | Cluster + ECR + 3 servicios Fargate + autoscaling + Cloud Map |
| `sqs.tf` | 2 colas + 2 DLQs + redrive |
| `dynamodb.tf` | `notification_events` (+GSI +Streams) + `subscriptions` |
| `secrets.tf` | Secrets Manager (HMAC por cliente) |
| `archive.tf` | Streams → Firehose → S3 (Parquet) + lifecycle + Athena/Glue |
| `observability.tf` | Alarmas SQS + Managed Grafana |
| `iam.tf` | Execution role + task roles por servicio (menor privilegio) |
| `kms.tf` | CMKs (DynamoDB, S3, Secrets) |

### Decisiones de estructura
- **Sin módulos**: con solo 2 colas y 3 servicios en un entregable de
  demostración, el costo de indirección de un módulo supera el beneficio de
  reutilización. Se priorizó la legibilidad de revisión (cada recurso a la
  vista). En producción, con más recursos o mantenimiento continuo, se
  extraería el patrón `sqs-with-dlq` y `ecs-service` a módulos.
- **State local** (`terraform.tfstate`) para el reto. En producción: backend S3
  + lock DynamoDB (ver comentario en `providers.tf`).
- **HTTP API** (no REST): más barata, JWT authorizer nativo de Cognito, VPC Link
  a Cloud Map **sin NLB**. Migrar a REST API solo si se necesitan API keys /
  usage plans por cliente.

## Aplicar
```bash
terraform init
terraform plan
terraform apply
```

## Despliegue de la aplicación (Opción B: tag inmutable)
Terraform crea la infraestructura y **referencia** la imagen de cada servicio en
ECR por `var.image_tag`. El código Java (Spring Boot hexagonal) es un repo
aparte; aquí solo se despliega la imagen ya construida.

Dockerfile de ejemplo (por servicio):
```dockerfile
FROM eclipse-temurin:21-jre
COPY target/app.jar /app.jar
ENTRYPOINT ["java","-jar","/app.jar"]
```

Flujo por servicio:
```bash
# 1) construir el jar
mvn -q clean package

# 2) construir y etiquetar la imagen con un tag inmutable (SHA del commit)
TAG=$(git rev-parse --short HEAD)
ECR=$(terraform output -json ecr_repositories | jq -r '."events-delivery"')
docker build -t $ECR:$TAG .

# 3) login + push a ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR
docker push $ECR:$TAG

# 4) desplegar esa versión
terraform apply -var="image_tag=$TAG"
```

### A futuro (Opción C · producción)
Que el pipeline (GitHub Actions / CodePipeline) registre nuevas task
definitions y actualice el service vía API de AWS, y que Terraform deje de
tocar el despliegue de código: descomentar en `ecs.tf`
`lifecycle { ignore_changes = [task_definition, desired_count] }`.

## Notas de diseño relevantes para el panel
- **Reintentos de entrega**: el backoff exponencial + jitter y el corte a los 6
  intentos viven en el **código** (worker, `ChangeMessageVisibility`), no en SQS.
  El `maxReceiveCount` de las DLQ es una **red de seguridad de infraestructura**.
- **Anti-SSRF (red)**: Fargate en subredes privadas sin IP pública; el único
  egreso a internet público (0.0.0.0/0 → NAT) es la entrega de webhooks; todo lo
  AWS-interno va por VPC Endpoints. Se complementa con IMDSv2/hop-limit y
  validación de URL en registro y entrega (código).
- **Aislamiento por cliente (A01)**: `client_id` como partition key en ambas
  tablas + scoping de query por el `client_id` del token en el core.
