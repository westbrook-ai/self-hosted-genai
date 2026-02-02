# Adds the NVIDIA Device Plugin to enable GPU access on Ollama pods
resource "helm_release" "nvidia_device_plugin" {
  name       = "nvidia-device-plugin"
  depends_on = [module.open-webui-eks]

  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  namespace  = "kube-system"
  version    = "0.15.0"
}

# Gateway API CRDs - required for ALB Controller Gateway API support
# Using null_resource to apply multi-document YAML via kubectl
resource "null_resource" "gateway_api_crds" {
  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --name ${local.cluster_name} --region ${local.region}
      kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
    EOT
  }

  depends_on = [module.open-webui-eks]
  
  triggers = {
    cluster_name = local.cluster_name
  }
}

# LBC-specific Gateway API CRDs (consolidated in v3.0.0+)
resource "null_resource" "lbc_gateway_crds" {
  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --name ${local.cluster_name} --region ${local.region}
      kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/refs/heads/main/config/crd/gateway/gateway-crds.yaml
    EOT
  }

  depends_on = [module.open-webui-eks, null_resource.gateway_api_crds]
  
  triggers = {
    cluster_name = local.cluster_name
  }
}

# ALB ingress controller
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "3.0.0"
  atomic     = true
  depends_on = [module.open-webui-eks, null_resource.gateway_api_crds, null_resource.lbc_gateway_crds]

  values = [
    templatefile("${path.module}/alb-controller-values.yaml", {
      cluster_name = local.cluster_name
      role_arn     = aws_iam_role.aws_load_balancer_controller.arn
      region       = local.region
      vpc_id       = module.vpc.vpc_id
    })
  ]
}

# External DNS controller
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = "kube-system"
  depends_on = [module.open-webui-eks]

  set = [
    {
      name  = "provider"
      value = "aws"
    },
    {
      name  = "domainFilters[0]"
      value = local.domain_name
    },
    {
      name  = "policy"
      value = "sync"
    },
    {
      name  = "registry"
      value = "txt"
    },
    {
      name  = "txtOwnerId"
      value = local.hosted_zone_id
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "external-dns"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.external_dns.arn
    },
    # Enable Gateway API HTTPRoute as a source for DNS records
    {
      name  = "sources[0]"
      value = "service"
    },
    {
      name  = "sources[1]"
      value = "ingress"
    },
    {
      name  = "sources[2]"
      value = "gateway-httproute"
    }
  ]
}

resource "helm_release" "ollama_small_chat" {
  name       = "ollama-small-chat"
  depends_on = [module.open-webui-eks, helm_release.nvidia_device_plugin]

  repository       = "https://otwld.github.io/ollama-helm"
  chart            = "ollama"
  namespace        = "genai"
  version          = "1.31.0"
  create_namespace = true

  # Models to load on Ollama on startup
  set_list = [{
    name  = "ollama.models.pull"
    value = local.chat_models
  }]

  # Enables Ollama to answer multiple requests concurrently
  set = [{
    name  = "ollama.extraEnv.OLLAMA_NUM_PARALLEL"
    value = 10
    },

    # Keeps models loaded in Ollama to prevent load delay
    {
      name  = "ollama.extraEnv.KEEP_ALIVE"
      value = "-1"
    }
  ]
}

resource "helm_release" "open_webui" {
  name       = "open-webui"
  depends_on = [module.open-webui-eks, helm_release.aws_load_balancer_controller]

  repository       = "https://helm.openwebui.com"
  chart            = "open-webui"
  namespace        = "genai"
  create_namespace = true
  version          = "8.1.0"

  # Sets the names of the Ollama services for Open WebUI to use 
  set_list = [
    {
      name  = "ollamaUrls"
      value = ["http://ollama-small-chat.genai.svc.cluster.local:11434"]
  }]

  # Disable the built-in Ollama deployment since we have multiple backends
  set = [{
    name  = "ollama.enabled"
    value = false
    },

    # Image takes a while to pull which slows down startup, so only pull if the image isn't present
    {
      name  = "image.pullPolicy"
      value = "IfNotPresent"
    },

    {
      name  = "persistence.enabled"
      value = "false"
    },

    {
      name  = "pipelines.persistence.enabled"
      value = "false"
    },

    # {
    #   name  = "image.tag"
    #   value = "v0.1.124"
    # },

    # {
    #   name  = "persistence.size"
    #   value = local.openwebui_pvc_size
    # },

    # Optional - uncomment if using GP3 storage, requires a separate StorageClass to be deployed
    # Read more here: https://aws.amazon.com/blogs/containers/migrating-amazon-eks-clusters-from-gp2-to-gp3-ebs-volumes/
    # {
    #   name = "persistence.storageClass"
    #   value = "gp3"
    # },

    # Set ingress on Open WebUI to provision access through AWS ALB
    {
      name  = "ingress.enabled"
      value = "true"
    },

    # Sets the external FQDN of the WebUI
    {
      name  = "ingress.annotations.external-dns\\.alpha\\.kubernetes\\.io/hostname"
      value = local.fqdn
    },

    {
      name  = "ingress.annotations.alb\\.ingress\\.kubernetes\\.io/load-balancer-name"
      value = "open-webui-alb"
    },

    {
      name  = "ingress.annotations.kubernetes\\.io/ingress\\.class"
      value = "alb"
    },

    {
      name  = "ingress.annotations.alb\\.ingress\\.kubernetes\\.io/target-type"
      value = "ip"
    },

    {
      name  = "ingress.annotations.alb\\.ingress\\.kubernetes\\.io/scheme"
      value = "internet-facing"
    },

    {
      name  = "ingress.annotations.alb\\.ingress\\.kubernetes\\.io/security-groups"
      value = aws_security_group.open-webui-ingress-sg.id
    },

    {
      name  = "ingress.annotations.alb\\.ingress\\.kubernetes\\.io/listen-ports"
      value = jsonencode([{ "HTTPS" : 443 }])
    },

    {
      name  = "ingress.annotations.alb\\.ingress\\.kubernetes\\.io/certificate-arn"
      value = aws_acm_certificate.webui.arn
    }
  ]
}
