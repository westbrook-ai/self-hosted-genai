# Edit the values below to match your desired configuration
locals {
  region = "us-west-2" # Region you want to deploy into
  # TODO: Make more generic
  vpc_name = "open-webui-vpc" # Name of VPC that will be created
  # TODO: Make more generic
  cluster_name = "open-webui-dev" # Name of the EKS cluster that will be created
  # TODO: Set to 1.35
  cluster_version    = "1.33"                                           # Version of EKS to use
  openwebui_pvc_size = "20Gi"                                           # Size of Open WebUI PVC; higher size = more documents stored for RAG
  chat_models        = ["llama3.2:3b"]                                  # Models to pre-load for chat
  domain_name        = "opensourceai.dev"                               # Route53 domain to use for the web UI hostname
  gateway_hostname   = "owui-gateway"                                   # Public hostname for Gateway API testing
  gateway_fqdn       = "${local.gateway_hostname}.${local.domain_name}" # FQDN for Gateway API

  # vLLM Production Stack configuration
  vllm_model_name          = "llama3-3b"                              # Name for the vLLM deployment
  vllm_model_url           = "meta-llama/Llama-3.2-3B-Instruct"       # HuggingFace model URL
  vllm_repository          = "vllm/vllm-openai"                       # Docker repository for vLLM
  vllm_tag                 = "v0.15.1-cu130"                          # Docker image tag (must match node CUDA driver)
  vllm_replica_count       = 1                                        # Number of replicas
  vllm_max_model_len       = 32768                                    # Max context length (A10G 24GB can't fit the full 131072)
  vllm_request_cpu         = 3                                        # CPU request per replica (g5.xlarge has ~4 allocatable)
  vllm_request_memory      = "12Gi"                                   # Memory request per replica (g5.xlarge has ~15Gi allocatable)
  vllm_request_gpu         = 1                                        # GPU request per replica
  vllm_tool_call_parser    = "llama3_json"                            # Parser for tool calls
  vllm_chat_template       = "tool_chat_template_llama3.1_json.jinja" # Chat template filename
  huggingface_token_secret = "huggingface-credentials"                # Name of k8s secret for HF token
}