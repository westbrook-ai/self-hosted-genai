# vLLM Production Stack — Helm Values Reference

Quick reference for common vLLM Production Stack Helm chart values. These are set via the `helm_release` resource in `vllm.tf`.

## Model Configuration

```hcl
modelSpec[0].name              = "llama3-3b"                          # Deployment identifier
modelSpec[0].repository        = "vllm/vllm-openai"                   # Docker image repo
modelSpec[0].tag               = "v0.15.1-cu130"                      # Docker image tag (must match CUDA driver)
modelSpec[0].modelURL          = "meta-llama/Llama-3.2-3B-Instruct"   # HuggingFace model path
```

## Scaling

```hcl
modelSpec[0].replicaCount      = 1                                # Number of replicas
```

## Resources

```hcl
# Resource requests (guaranteed)
modelSpec[0].requestCPU        = 3                                # CPU cores
modelSpec[0].requestMemory     = "12Gi"                           # Memory
modelSpec[0].requestGPU        = 1                                # GPU count

# Resource limits (optional, max allowed)
modelSpec[0].limitCPU          = "4"                              # Max CPU cores
modelSpec[0].limitMemory       = "15Gi"                           # Max memory
# Note: GPU limits are automatically set to match requests
```

## Tool Calling

```hcl
modelSpec[0].enableTool        = "true"                           # Enable tool calling
modelSpec[0].toolCallParser    = "llama3_json"                    # Parser type
modelSpec[0].chatTemplate      = "tool_chat_template_llama3.1_json.jinja"
```

Available parsers:
- `llama3_json` — For Llama 3.x models
- `hermes` — For Hermes models
- `mistral` — For Mistral models

## vLLM Engine Configuration

```hcl
# Set via vllmConfig in the Helm values
modelSpec[0].vllmConfig.maxModelLen = 32768                       # Max context length
```

## Environment Variables

```hcl
modelSpec[0].env[0].name                               = "HUGGING_FACE_HUB_TOKEN"
modelSpec[0].env[0].valueFrom.secretKeyRef.name        = "huggingface-credentials"
modelSpec[0].env[0].valueFrom.secretKeyRef.key         = "HUGGING_FACE_HUB_TOKEN"
```

## Volume Mounts

The chat template is passed via Helm `values` (not `set`) because the Jinja content is too complex for `--set`. The chart creates a ConfigMap from the template content and mounts it automatically.

## Advanced vLLM Arguments

```hcl
# Custom vLLM engine arguments
modelSpec[0].args[0]           = "--max-model-len"
modelSpec[0].args[1]           = "4096"
modelSpec[0].args[2]           = "--tensor-parallel-size"
modelSpec[0].args[3]           = "1"
modelSpec[0].args[4]           = "--gpu-memory-utilization"
modelSpec[0].args[5]           = "0.9"
```

Common vLLM arguments:
- `--max-model-len` - Maximum sequence length
- `--tensor-parallel-size` - Number of GPUs for tensor parallelism
- `--gpu-memory-utilization` - Fraction of GPU memory to use (0.0-1.0)
- `--quantization` - Quantization method (e.g., "awq", "gptq")
- `--dtype` - Data type (e.g., "auto", "float16", "bfloat16")

## Runtime Configuration

```hcl
# Node selector
modelSpec[0].nodeSelector.workload = "gpu"

# Tolerations for GPU-tainted nodes
modelSpec[0].tolerations[0].key      = "nvidia.com/gpu"
modelSpec[0].tolerations[0].operator = "Equal"
modelSpec[0].tolerations[0].value    = "true"
modelSpec[0].tolerations[0].effect   = "NoSchedule"
```

### Service Configuration

```hcl
# Router service type
routerService.type                 = "LoadBalancer"
routerService.port                 = 80

# Service annotations
routerService.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-type = "nlb"
```

## Example Configurations

### Larger Model (8B on g5.2xlarge)

```hcl
vllm_model_url      = "meta-llama/Llama-3.1-8B-Instruct"
vllm_request_cpu    = 6
vllm_request_memory = "24Gi"
vllm_request_gpu    = 1
vllm_max_model_len  = 32768
```

### High-Memory Model (70B, multi-GPU)

```hcl
vllm_model_url      = "meta-llama/Llama-3.1-70B-Instruct"
vllm_request_cpu    = 16
vllm_request_memory = "128Gi"
vllm_request_gpu    = 4
```

Requires a larger GPU instance type (e.g., `g5.12xlarge`) in the `gpu-small` node group in `eks.tf`.

### Quantized Model (AWQ)

Add to helm_release in vllm.tf:

```hcl
{
  name  = "modelSpec[0].args[0]"
  value = "--quantization"
},
{
  name  = "modelSpec[0].args[1]"
  value = "awq"
}
```

### Multiple Replicas for Load Balancing

```hcl
vllm_replica_count = 3
```

### Custom GPU Memory Utilization

Add to helm_release in vllm.tf:

```hcl
{
  name  = "modelSpec[0].args[0]"
  value = "--gpu-memory-utilization"
},
{
  name  = "modelSpec[0].args[1]"
  value = "0.85"
}
```

## OpenTofu Pattern

All values are set using the `set` array in the `helm_release` resource in `vllm.tf`:

```hcl
resource "helm_release" "vllm_production_stack" {
  # ...
  
  set = [
    {
      name  = "servingEngineSpec.modelSpec[0].name"
      value = local.vllm_model_name
    },
  ]
}
```

For complex nested content (e.g., chat templates), use `values` with `yamlencode` instead of `set`.

## Resources

- [vLLM Production Stack Helm Values](https://github.com/vllm-project/production-stack/blob/main/helm/values.yaml)
- [vLLM Engine Arguments](https://docs.vllm.ai/en/latest/models/engine_args.html)
