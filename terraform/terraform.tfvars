# Kaloora AWS EKS Deployment Variables
aws_region           = "us-east-1"
project_name         = "kaloora-eks"
environment          = "dev"
cluster_version      = "1.36"
worker_instance_type = "t3.small"
worker_count         = 2
asg_min_size         = 2
asg_max_size         = 4
root_volume_size     = 20
