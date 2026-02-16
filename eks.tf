# Latest AL2023 GPU-enabled EKS AMI
data "aws_ami" "eks_gpu_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-al2023-x86_64-nvidia-${local.cluster_version}-*"]
  }

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Latest AL2023 standard EKS AMI
data "aws_ami" "eks_al2023_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-al2023-x86_64-standard-${local.cluster_version}-*"]
  }

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

module "open-webui-eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.cluster_name
  kubernetes_version = local.cluster_version

  endpoint_public_access = true

  addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      before_compute = true
      most_recent    = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = aws_iam_role.ebs_csi_driver_role.arn
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets
  security_group_name      = "open-webui-eks-cluster"
  node_security_group_name = "open-webui-eks-nodes"

  node_security_group_additional_rules = {
    alb_ingress = {
      description              = "Access from Gateway ALB to Open WebUI on port 8080"
      protocol                 = "tcp"
      from_port                = 8080
      to_port                  = 8080
      type                     = "ingress"
      source_security_group_id = aws_security_group.open-webui-ingress-sg.id
    }
  }

  eks_managed_node_groups = {
    open-webui = {
      min_size     = 1
      max_size     = 1
      desired_size = 1

      ami_id         = data.aws_ami.eks_al2023_ami.id
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["m5a.large"]
      capacity_type  = "ON_DEMAND"

      enable_bootstrap_user_data = true

      # Adds a disk large enough to store user data and files uploaded for RAG 
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 100
            volume_type           = "gp2"
            delete_on_termination = true
          }
        }
      }

      # Adds IAM permissions to node role
      create_iam_role = true
      iam_role_name   = "open-webui-eks-node-group"
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }

      # Adds Kubernetes labels used for pod placement 
      labels = {
        "workload" = "general"
      }

      tags = {
        "kubernetes.io/cluster/${local.cluster_name}" = "owned"
      }
    }

    gpu-small = {
      min_size     = 1
      max_size     = 1
      desired_size = 1

      ami_id         = data.aws_ami.eks_gpu_ami.id
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["g5.xlarge"]
      capacity_type  = "ON_DEMAND"

      enable_bootstrap_user_data = true

      create_iam_role = true
      iam_role_name   = "gpu-small-eks-node-group"
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }

      # Adds a disk large enough to store models and container images
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 100
            volume_type           = "gp2"
            delete_on_termination = true
          }
        }
      }

      tags = {
        "kubernetes.io/cluster/${local.cluster_name}" = "owned"
      }

      # Adds Kubernetes labels used for pod placement
      labels = {
        "workload" = "gpu"
      }

      # Taint GPU nodes so only pods with matching tolerations are scheduled
      taints = {
        gpu = {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  enable_cluster_creator_admin_permissions = true
}
