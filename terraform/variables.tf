variable "aws_region" {
  description = "Regione AWS di destinazione per tutte le risorse"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "aws_region deve essere un identificatore di regione AWS valido (es. us-east-1, eu-west-1)."
  }
}

variable "project_name" {
  description = "Nome del progetto usato come prefisso per le risorse"
  type        = string
  default     = "kaloora-eks"
}

variable "environment" {
  description = "Ambiente di deploy (dev, test, prod)"
  type        = string
  default     = "test"

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment deve essere uno tra 'dev', 'test' o 'prod'."
  }
}

# ── EKS & Kubernetes Configuration ─────────────────────────────────────────────

variable "cluster_version" {
  description = "Versione di Kubernetes per il cluster EKS"
  type        = string
  default     = "1.36"
}

variable "worker_instance_type" {
  description = "Tipo di istanza EC2 per i nodi Worker EKS Managed Node Group"
  type        = string
  default     = "t3.small"
}

variable "worker_count" {
  description = "Numero desiderato di nodi worker nell'EKS Managed Node Group"
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 10
    error_message = "worker_count deve essere compreso tra 1 e 10."
  }
}

variable "asg_min_size" {
  description = "Numero minimo di nodi worker nell'EKS Managed Node Group"
  type        = number
  default     = 2

  validation {
    condition     = var.asg_min_size >= 1 && var.asg_min_size <= 10
    error_message = "asg_min_size deve essere compreso tra 1 e 10."
  }
}

variable "asg_max_size" {
  description = "Numero massimo di nodi worker nell'EKS Managed Node Group"
  type        = number
  default     = 4

  validation {
    condition     = var.asg_max_size >= 1 && var.asg_max_size <= 10
    error_message = "asg_max_size deve essere compreso tra 1 e 10."
  }
}

variable "root_volume_size" {
  description = "Dimensione in GB del volume EBS gp3 per ciascun nodo worker EKS"
  type        = number
  default     = 20

  validation {
    condition     = var.root_volume_size >= 20 && var.root_volume_size <= 100
    error_message = "root_volume_size deve essere compreso tra 20 e 100 GB."
  }
}

# ── Database & Secret Defaults ─────────────────────────────────────────────────

variable "db_username" {
  description = "Master username per PostgreSQL RDS"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "Master password per PostgreSQL RDS (se non fornita, viene generata casualmente)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "db_name" {
  description = "Nome del database iniziale PostgreSQL"
  type        = string
  default     = "userdb"
}

variable "jwt_secret" {
  description = "Chiave segreta per la firma dei token JWT (minimo 32 caratteri, se non fornita viene generata casualmente)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "redis_auth_token" {
  description = "Auth token per Redis ElastiCache (minimo 16 caratteri, se non fornito viene generato casualmente)"
  type        = string
  default     = ""
  sensitive   = true
}
