# Self-Hosted GenAI on Amazon EKS

Deploy a self-hosted AI inference stack on Amazon EKS using OpenTofu. This repo provisions an EKS cluster with GPU nodes, deploys [vLLM Production Stack](https://github.com/vllm-project/production-stack) for high-performance inference with tool calling, [Ollama](https://ollama.com/) for lightweight model serving, and [Open WebUI](https://openwebui.com/) as a web interface — all behind HTTPS via the Kubernetes Gateway API.

## What's Included

- **vLLM Production Stack** — GPU-accelerated inference with OpenAI-compatible API and tool calling support
- **Ollama** — Simple model serving for chat and FIM (fill-in-the-middle) use cases
- **Open WebUI** — Web UI for interacting with all deployed models
- **Gateway API + AWS ALB** — HTTPS ingress with ACM certificate and Route53 DNS
- **EKS with GPU Nodes** — Managed Kubernetes with `g5.xlarge` (NVIDIA A10G) GPU nodes

## Prerequisites

You will need the following installed locally:

| Tool | Purpose |
|------|---------|
| [OpenTofu](https://opentofu.org/docs/intro/install/) | Infrastructure provisioning |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Kubernetes cluster management |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | AWS authentication and EKS kubeconfig |
| [Helm](https://helm.sh/docs/intro/install/) | Used by OpenTofu's Helm provider |

You also need:

1. **An AWS account with a Route53 Public Hosted Zone.** A domain is required — an ACM certificate is provisioned for HTTPS on the Open WebUI hostname.
2. **A HuggingFace account and API token.** Required for downloading gated models like Llama. [Create a token here.](https://huggingface.co/settings/tokens) You must also accept the license for the model you plan to use (e.g., [Llama-3.2-3B-Instruct](https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct)).

## Costs

> **Warning:** The `g5.xlarge` instances used here cost ~$1/hour in `us-west-2`. This setup can easily cost **$50/day** if left running. Destroy resources when not in use.

## Security

This deployment is open to the internet by default. Restrict access by updating `aws_security_group.open-webui-ingress-sg` in `vpc.tf`.

## Quickstart

### 1. Clone and Configure

```bash
git clone https://github.com/westbrook-ai/self-hosted-genai && cd self-hosted-genai
```

Edit `locals.tf` to set your configuration. Key values to review:

| Local | Description | Default |
|-------|-------------|---------|
| `region` | AWS region | `us-west-2` |
| `domain_name` | Route53 hosted zone | `opensourceai.dev` |
| `gateway_hostname` | Public hostname for the UI | `owui-gateway` |
| `vllm_model_url` | HuggingFace model to serve | `meta-llama/Llama-3.2-3B-Instruct` |
| `vllm_tag` | vLLM Docker image tag (must match node CUDA driver) | `v0.15.1-cu130` |
| `chat_models` | Ollama models to pre-load | `["llama3.2:3b"]` |

All values are commented in the file.

### 2. Set Your HuggingFace Token

```bash
export TF_VAR_huggingface_token="hf_your_token_here"
```

### 3. Deploy

```bash
tofu init
tofu apply
```

The apply takes 20–25 minutes. By default, state is stored locally — update `backend.tf` to use S3 or another backend if desired.

### 4. Access Open WebUI

Once the apply completes, update your kubeconfig and verify pods are running:

```bash
aws eks update-kubeconfig --name open-webui-dev --region us-west-2
kubectl get pods -n genai
```

Navigate to your configured FQDN (e.g., `https://owui-gateway.opensourceai.dev`). Use **Sign Up** to create the first admin user.

## Testing vLLM

For instructions on port-forwarding the vLLM router and testing completions, tool calling, and model listing, see [VLLM_SETUP.md](VLLM_SETUP.md).

## Configuration

### Changing Models

Update `vllm_model_url` in `locals.tf` and adjust resource requests to match the model's requirements:

```hcl
vllm_model_url      = "meta-llama/Llama-3.1-8B-Instruct"
vllm_request_cpu    = 3
vllm_request_memory = "12Gi"
vllm_request_gpu    = 1
vllm_max_model_len  = 32768
```

Then run `tofu apply`.

For larger models, you'll also need to update the GPU node group instance type in `eks.tf` (e.g., `g5.2xlarge` for 8B+ models, `g5.12xlarge` for 70B).

### Scaling

Set `vllm_replica_count` in `locals.tf` and ensure enough GPU nodes are available by updating `max_size` / `desired_size` on the `gpu-small` node group.

### vLLM Helm Reference

For a detailed reference of available vLLM Production Stack Helm values, see [VLLM_REFERENCE.md](VLLM_REFERENCE.md).

## Cleaning Up

Destroy all resources to stop incurring costs:

```bash
tofu destroy
```

I have occassionally observed VPC resources not deleting correctly on the first try. You may need to run a second `tofu destroy` command if it fails on the first try. The only resources that had trouble deleting are resources that should not cost money. 
