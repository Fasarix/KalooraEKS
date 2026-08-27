# ── Security Groups per EKS, ALB, RDS ed ElastiCache ──────────────────────────

# ── 1. Security Group per il Control Plane di EKS ──────────────────────────────

resource "aws_security_group" "eks_cluster" {
  name        = "${var.project_name}-eks-cluster-sg"
  description = "Security Group per il Control Plane di Amazon EKS"
  vpc_id      = aws_vpc.main.id

  # Ingress HTTPS (443) dai nodi worker e dalla VPC per le chiamate all'API Server
  ingress {
    description     = "HTTPS from Worker Nodes"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.k8s_nodes.id]
  }

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-eks-cluster-sg"
  }
}

# ── 2. Security Group per i Nodi Worker EKS ────────────────────────────────────

resource "aws_security_group" "k8s_nodes" {
  name        = "${var.project_name}-k8s-nodes-sg"
  description = "Security Group per i nodi worker del cluster EKS"
  vpc_id      = aws_vpc.main.id

  # NodePort Ingress solo dall'Application Load Balancer (ALB)
  ingress {
    description     = "NodePort Ingress only from ALB"
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Comunicazione bidirezionale con il Control Plane EKS (Kubelet, logs, exec)
  ingress {
    description = "Cluster Control Plane communication"
    from_port   = 10250
    to_port     = 10255
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  ingress {
    description = "All VPC intra-cluster traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  ingress {
    description = "Inter-node self traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Egress completo verso Internet (per scaricare pacchetti, immagini ECR e chiamare AWS APIs)
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name                                                  = "${var.project_name}-k8s-nodes-sg"
    "kubernetes.io/cluster/${var.project_name}-cluster" = "shared"
  }
}

# ── 3. Security Group per RDS PostgreSQL ───────────────────────────────────────

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security Group per RDS PostgreSQL (accetta traffico solo dai nodi K8s)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from K8s nodes and VPC"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.k8s_nodes.id]
    cidr_blocks     = [aws_vpc.main.cidr_block]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# ── 4. Security Group per ElastiCache Redis ────────────────────────────────────

resource "aws_security_group" "elasticache" {
  name        = "${var.project_name}-elasticache-sg"
  description = "Security Group per ElastiCache Redis (accetta traffico solo dai nodi K8s)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from K8s nodes and VPC"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.k8s_nodes.id]
    cidr_blocks     = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-elasticache-sg"
  }
}

# ── 5. Regola Ingress NodePort sul Cluster Security Group di EKS ───────────────

resource "aws_security_group_rule" "eks_nodeport_from_alb" {
  type                     = "ingress"
  description              = "NodePort Ingress from ALB to EKS Managed Nodes"
  from_port                = 30000
  to_port                  = 32767
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.alb.id
}
