# vLLM Production Stack Resources

# Kubernetes Secret for HuggingFace credentials
# NOTE: You must set the HUGGINGFACE_TOKEN environment variable before applying
# Example: export TF_VAR_huggingface_token="hf_your_token_here"
variable "huggingface_token" {
  description = "HuggingFace API token for accessing gated models like Llama"
  type        = string
  sensitive   = true
  default     = ""
}

resource "kubernetes_secret_v1" "huggingface_credentials" {
  metadata {
    name      = local.huggingface_token_secret
    namespace = "genai"
  }

  data = {
    HUGGING_FACE_HUB_TOKEN = var.huggingface_token
  }

  type = "Opaque"

  depends_on = [helm_release.open_webui] # Ensures genai namespace exists
}

# vLLM Production Stack Helm Release
resource "helm_release" "vllm_production_stack" {
  name = "vllm"
  depends_on = [
    module.open-webui-eks,
    helm_release.nvidia_device_plugin,
    kubernetes_secret_v1.huggingface_credentials
  ]

  repository       = "https://vllm-project.github.io/production-stack"
  chart            = "vllm-stack"
  namespace        = "genai"
  version          = "0.1.9" # Check for latest version at https://github.com/vllm-project/production-stack
  create_namespace = false   # Namespace already created by open_webui
  timeout          = 600     # vLLM model loading can take several minutes

  # The chat template is passed via values (not set) because the jinja content
  # is too complex for --set. The chart natively creates a ConfigMap from this
  # and mounts it at /templates in the vLLM container.
  values = [yamlencode({
    servingEngineSpec = {
      modelSpec = [{
        chatTemplateConfigMap = file("${path.module}/templates/tool_chat_template_llama3.1_json.jinja")
      }]
    }
    routerSpec = {
      # Give the router time to start and discover engines before probes kick in
      livenessProbe = {
        initialDelaySeconds = 60
        periodSeconds       = 10
        failureThreshold    = 6
        httpGet             = { path = "/health" }
      }
      startupProbe = {
        initialDelaySeconds = 10
        periodSeconds       = 10
        failureThreshold    = 30
        httpGet             = { path = "/health" }
      }
      readinessProbe = {
        initialDelaySeconds = 60
        periodSeconds       = 10
        failureThreshold    = 6
        httpGet             = { path = "/health" }
      }
    }
  })]

  set = [
    # Model specification
    {
      name  = "servingEngineSpec.runtimeClassName"
      value = ""
    },
    {
      name  = "servingEngineSpec.modelSpec[0].name"
      value = local.vllm_model_name
    },
    {
      name  = "servingEngineSpec.modelSpec[0].repository"
      value = local.vllm_repository
    },
    {
      name  = "servingEngineSpec.modelSpec[0].tag"
      value = local.vllm_tag
    },
    {
      name  = "servingEngineSpec.modelSpec[0].modelURL"
      value = local.vllm_model_url
    },

    # Max context length (A10G 24GB can't fit the model's full 131072 context)
    {
      name  = "servingEngineSpec.modelSpec[0].vllmConfig.maxModelLen"
      value = local.vllm_max_model_len
    },

    # Replica configuration
    {
      name  = "servingEngineSpec.modelSpec[0].replicaCount"
      value = local.vllm_replica_count
    },

    # Resource requests
    {
      name  = "servingEngineSpec.modelSpec[0].requestCPU"
      value = local.vllm_request_cpu
    },
    {
      name  = "servingEngineSpec.modelSpec[0].requestMemory"
      value = local.vllm_request_memory
    },
    {
      name  = "servingEngineSpec.modelSpec[0].requestGPU"
      value = local.vllm_request_gpu
    },

    # Tool calling configuration
    {
      name  = "servingEngineSpec.modelSpec[0].enableTool"
      value = "true"
    },
    {
      name  = "servingEngineSpec.modelSpec[0].toolCallParser"
      value = local.vllm_tool_call_parser
    },
    {
      name  = "servingEngineSpec.modelSpec[0].chatTemplate"
      value = local.vllm_chat_template
    },

    # HuggingFace credentials environment variable
    {
      name  = "servingEngineSpec.modelSpec[0].env[0].name"
      value = "HUGGING_FACE_HUB_TOKEN"
    },
    {
      name  = "servingEngineSpec.modelSpec[0].env[0].valueFrom.secretKeyRef.name"
      value = local.huggingface_token_secret
    },
    {
      name  = "servingEngineSpec.modelSpec[0].env[0].valueFrom.secretKeyRef.key"
      value = "HUGGING_FACE_HUB_TOKEN"
    },

    # CUDA compat fix: The vLLM Docker image ships a CUDA compat libcuda.so
    # that is older than the host driver on EKS GPU AMI (driver 580.x).
    # The container's ldconfig cache puts the compat lib first, causing
    # "Error 803: unsupported display driver / cuda driver combination".
    # Fix: prioritize the host-injected driver path (/usr/lib64) before
    # the container's compat path. See: github.com/vllm-project/vllm/issues/32373
    {
      name  = "servingEngineSpec.modelSpec[0].env[1].name"
      value = "LD_LIBRARY_PATH"
    },
    {
      name  = "servingEngineSpec.modelSpec[0].env[1].value"
      value = "/usr/lib64:/usr/local/cuda/lib64:/usr/local/lib/python3.12/dist-packages/torch/lib:/usr/local/lib/python3.12/dist-packages/nvidia/cudnn/lib"
    },

    # Node selector to ensure vLLM runs on GPU nodes only
    {
      name  = "servingEngineSpec.modelSpec[0].nodeSelector.workload"
      value = "gpu"
    },

    # Toleration to allow scheduling on tainted GPU nodes
    {
      name  = "servingEngineSpec.modelSpec[0].tolerations[0].key"
      value = "nvidia.com/gpu"
    },
    {
      name  = "servingEngineSpec.modelSpec[0].tolerations[0].operator"
      value = "Equal"
    },
    {
      name  = "servingEngineSpec.modelSpec[0].tolerations[0].value"
      value = "true"
      type  = "string"
    },
    {
      name  = "servingEngineSpec.modelSpec[0].tolerations[0].effect"
      value = "NoSchedule"
    },

    # Pod anti-affinity: only one vLLM serving engine pod per GPU node
    {
      name  = "servingEngineSpec.modelSpec[0].affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].labelSelector.matchExpressions[0].key"
      value = "model"
    },
    {
      name  = "servingEngineSpec.modelSpec[0].affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].labelSelector.matchExpressions[0].operator"
      value = "Exists"
    },
    {
      name  = "servingEngineSpec.modelSpec[0].affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].topologyKey"
      value = "kubernetes.io/hostname"
    },

    # Router resource overrides (defaults inherit model spec, which is too large)
    {
      name  = "routerSpec.resources.requests.cpu"
      value = "400m"
    },
    {
      name  = "routerSpec.resources.requests.memory"
      value = "1Gi"
    },
    {
      name  = "routerSpec.resources.limits.cpu"
      value = "1"
    },
    {
      name  = "routerSpec.resources.limits.memory"
      value = "1Gi"
    },

    # Router runs on general nodes (no GPU needed)
    {
      name  = "routerSpec.nodeSelector.workload"
      value = "general"
    }
  ]
}
