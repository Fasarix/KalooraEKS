# ── Terraform Outputs per AWS EKS, ALB, Database e Frontend ───────────────────

# ── 1. Amazon EKS Cluster ─────────────────────────────────────────────────────

output "eks_cluster_name" {
  description = "Nome del cluster Amazon EKS"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint API Server del cluster Amazon EKS"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_arn" {
  description = "ARN del cluster Amazon EKS"
  value       = aws_eks_cluster.main.arn
}

output "eks_cluster_certificate_authority_data" {
  description = "Certificato CA del cluster Amazon EKS (base64)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "eks_node_group_arn" {
  description = "ARN del Managed Node Group dei Worker EKS"
  value       = aws_eks_node_group.workers.arn
}

output "configure_kubectl_command" {
  description = "Comando AWS CLI per configurare automaticamente kubectl locale"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

# ── 2. AWS Application Load Balancer (ALB) ────────────────────────────────────

output "alb_dns_name" {
  description = "DNS pubblico dell'AWS Application Load Balancer"
  value       = aws_lb.main.dns_name
}

# ── 3. Databases & Messaging ──────────────────────────────────────────────────

output "rds_postgres_endpoint" {
  description = "Endpoint di connessione a RDS PostgreSQL"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_postgres_address" {
  description = "Host di connessione a RDS PostgreSQL"
  value       = aws_db_instance.postgres.address
}

output "dynamodb_diary_table" {
  description = "Nome tabella DynamoDB per il diario pasti"
  value       = aws_dynamodb_table.diary.name
}

output "dynamodb_foods_table" {
  description = "Nome tabella DynamoDB per gli alimenti e ricette"
  value       = aws_dynamodb_table.foods.name
}

output "sqs_queue_url" {
  description = "URL della coda Amazon SQS per gli eventi diario"
  value       = aws_sqs_queue.diary_events.url
}

output "elasticache_redis_endpoint" {
  description = "Endpoint host di ElastiCache Redis"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

# ── 4. Frontend & CloudFront ──────────────────────────────────────────────────

output "s3_frontend_bucket" {
  description = "Nome del bucket S3 per il deploy del frontend"
  value       = aws_s3_bucket.frontend.id
}

output "cloudfront_domain_name" {
  description = "URL pubblico CloudFront per accedere alla WebApp Kaloora"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "ID della distribuzione CloudFront per invalidazione cache"
  value       = aws_cloudfront_distribution.frontend.id
}

output "aws_region" {
  description = "Regione AWS utilizzata per il deployment"
  value       = var.aws_region
}

# ── 5. ECR Repositories ───────────────────────────────────────────────────────

output "ecr_repository_urls" {
  description = "URL dei repository ECR per i container"
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}
