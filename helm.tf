# Adds the NVIDIA Device Plugin to enable GPU access on Ollama pods
resource "helm_release" "nvidia_device_plugin" {
  name       = "nvidia-device-plugin"
  depends_on = [module.open-webui-eks]

  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  namespace  = "kube-system"
  version    = "0.15.0"

  set = [
    {
      name  = "affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key"
      value = "workload"
    },
    {
      name  = "affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator"
      value = "In"
    },
    {
      name  = "affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0]"
      value = "gpu"
    },

    # Toleration to allow scheduling on tainted GPU nodes
    {
      name  = "tolerations[0].key"
      value = "nvidia.com/gpu"
    },
    {
      name  = "tolerations[0].operator"
      value = "Equal"
    },
    {
      name  = "tolerations[0].value"
      value = "true"
      type  = "string"
    },
    {
      name  = "tolerations[0].effect"
      value = "NoSchedule"
    }
  ]
}

# Gateway API CRDs - required for ALB Controller Gateway API support
# Using null_resource because the gateway-api project does not publish a Helm chart;
# CRDs are distributed as raw YAML from GitHub releases.
resource "null_resource" "gateway_api_crds" {
  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --name ${local.cluster_name} --region ${local.region}
      kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml --ignore-not-found"
  }

  depends_on = [module.open-webui-eks]

  triggers = {
    cluster_name = local.cluster_name
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "3.0.0"
  atomic     = true
  depends_on = [module.open-webui-eks, null_resource.gateway_api_crds]

  set = [
    {
      name  = "clusterName"
      value = local.cluster_name
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.aws_load_balancer_controller.arn
    },
    {
      name  = "region"
      value = local.region
    },
    {
      name  = "vpcId"
      value = module.vpc.vpc_id
    },
    {
      name  = "controllerConfig.featureGates.ALBGatewayAPI"
      value = "true"
    },
    {
      name  = "controllerConfig.featureGates.NLBGatewayAPI"
      value = "false"
    },
    {
      name  = "nodeSelector.workload"
      value = "general"
    }
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
      value = data.aws_route53_zone.webui.zone_id
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
    },
    {
      name  = "nodeSelector.workload"
      value = "general"
    }
  ]
}

resource "helm_release" "ollama_small_chat" {
  name       = "ollama-small-chat"
  depends_on = [module.open-webui-eks, helm_release.nvidia_device_plugin]

  repository       = "https://otwld.github.io/ollama-helm"
  chart            = "ollama"
  namespace        = "genai"
  version          = "1.42.0"
  create_namespace = true

  # Models to load on Ollama on startup
  set_list = [{
    name  = "ollama.models.pull"
    value = local.chat_models
  }]

  # Scale to 0 replicas while vLLM is active
  set = [{
    name  = "replicaCount"
    value = 0
    },

    # Enables Ollama to answer multiple requests concurrently
    {
      name  = "ollama.extraEnv.OLLAMA_NUM_PARALLEL"
      value = 10
    },

    # Keeps models loaded in Ollama to prevent load delay
    {
      name  = "ollama.extraEnv.KEEP_ALIVE"
      value = "-1"
    },

    # Node selector to ensure Ollama runs on GPU nodes only
    {
      name  = "nodeSelector.workload"
      value = "gpu"
    },

    # GPU resource request
    {
      name  = "ollama.gpu.enabled"
      value = "true"
    },
    {
      name  = "ollama.gpu.number"
      value = 1
    },

    # Toleration to allow scheduling on tainted GPU nodes
    {
      name  = "tolerations[0].key"
      value = "nvidia.com/gpu"
    },
    {
      name  = "tolerations[0].operator"
      value = "Equal"
    },
    {
      name  = "tolerations[0].value"
      value = "true"
      type  = "string"
    },
    {
      name  = "tolerations[0].effect"
      value = "NoSchedule"
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
  version          = "12.0.1"

  set_list = [
    {
      name  = "ollamaUrls"
      value = ["http://ollama-small-chat.genai.svc.cluster.local:11434"]
    },
    {
      name  = "openaiBaseApiUrls"
      value = ["http://vllm-tool-router-service.genai.svc.cluster.local/v1"]
    },
    {
      name  = "openaiApiKeys"
      value = ["not-needed"]
    },
    {
      name  = "route.hostnames"
      value = [local.gateway_fqdn]
    }
  ]

  set = [{
    name  = "ollama.enabled"
    value = false
    },
    {
      name  = "image.pullPolicy"
      value = "IfNotPresent"
    },

    {
      name  = "persistence.enabled"
      value = "false"
    },

    {
      name  = "persistence.size"
      value = local.openwebui_pvc_size
    },

    # Optional - uncomment if using GP3 storage, requires a separate StorageClass to be deployed
    # Read more here: https://aws.amazon.com/blogs/containers/migrating-amazon-eks-clusters-from-gp2-to-gp3-ebs-volumes/
    # {
    #   name = "persistence.storageClass"
    #   value = "gp3"
    # },

    {
      name  = "pipelines.enabled"
      value = "true"
    },

    {
      name  = "pipelines.persistence.enabled"
      value = "false"
    },

    {
      name  = "ingress.enabled"
      value = "false"
    },

    # Gateway API HTTPRoute
    {
      name  = "route.enabled"
      value = "true"
    },
    {
      name  = "route.apiVersion"
      value = "gateway.networking.k8s.io/v1"
    },
    {
      name  = "route.kind"
      value = "HTTPRoute"
    },
    {
      name  = "route.annotations.external-dns\\.alpha\\.kubernetes\\.io/hostname"
      value = local.gateway_fqdn
    },

    # Parent gateway reference
    {
      name  = "route.parentRefs[0].name"
      value = "open-webui-gateway"
    },
    {
      name  = "route.parentRefs[0].namespace"
      value = "genai"
    },
    {
      name  = "route.parentRefs[0].sectionName"
      value = "https"
    },

    # Must be deployed at root - Open WebUI uses absolute paths for frontend assets
    {
      name  = "route.matches[0].path.type"
      value = "PathPrefix"
    },
    {
      name  = "route.matches[0].path.value"
      value = "/"
    },
    {
      name  = "route.httpsRedirect"
      value = "false"
    },

    # Node selector to ensure Open WebUI runs on non-GPU nodes only
    {
      name  = "nodeSelector.workload"
      value = "general"
    },

    # Pipelines node selector
    {
      name  = "pipelines.nodeSelector.workload"
      value = "general"
    },

    # Redis node selector
    {
      name  = "redis.nodeSelector.workload"
      value = "general"
    }
  ]
}
