# ── Amazon Elastic Kubernetes Service (EKS Managed Cluster & Node Group) ───────

# ── 1. EKS Cluster (Managed Control Plane) ────────────────────────────────────

resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = [aws_subnet.public_1.id, aws_subnet.public_2.id, aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller
  ]

  tags = {
    Name = "${var.project_name}-eks-cluster"
  }
}

# ── 2. EKS Managed Node Group Launch Template (IMDSv2 Hop Limit = 2) ──────────

resource "aws_launch_template" "eks_nodes" {
  name_prefix   = "${var.project_name}-node-lt-"
  instance_type = var.worker_instance_type

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-worker"
      Role        = "worker"
      Project     = "KalooraEKS"
      Environment = var.environment
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── 3. EKS Managed Node Group (Worker Instances) ──────────────────────────────

resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-workers"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  capacity_type   = "ON_DEMAND"

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = "$Latest"
  }

  scaling_config {
    desired_size = var.worker_count
    min_size     = var.asg_min_size
    max_size     = var.asg_max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name        = "${var.project_name}-worker"
    Role        = "worker"
    Project     = "KalooraEKS"
    Environment = var.environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_read_only,
    aws_iam_role_policy_attachment.kaloora_services_attach
  ]
}

# ── 4. Collegamento Dinamico tra i Nodi EKS e il Target Group dell'ALB ────────

resource "aws_autoscaling_attachment" "eks_nodes_to_alb" {
  autoscaling_group_name = aws_eks_node_group.workers.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.k8s_ingress.arn
}

# ── 5. EKS Managed Add-ons ────────────────────────────────────────────────────

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"

  depends_on = [
    aws_eks_node_group.workers
  ]
}

# ── 6. IAM OIDC Provider per IAM Roles for Service Accounts (IRSA) ────────────

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name = "${var.project_name}-eks-irsa"
  }
}
