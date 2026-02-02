# Edit the values below to match your desired configuration
locals {
  region             = "us-west-2"        # Region you want to deploy into
  vpc_name           = "open-webui-vpc"   # Name of VPC that will be created
  cluster_name       = "open-webui-dev"   # Name of the EKS cluster that will be created
  cluster_version    = "1.33"             # Version of EKS to use
  openwebui_pvc_size = "20Gi"             # Size of Open WebUI PVC; higher size = more documents stored for RAG
  chat_models        = ["llama3.2:3b"]    # Models to pre-load for chat
  domain_name        = "opensourceai.dev" # Route53 domain to use for the web UI hostname
  public_hostname    = "owui-test"        # Public hostname to use for UI hostname (Ingress)
  gateway_hostname   = "owui-gateway"     # Public hostname for Gateway API testing
  hosted_zone_id     = "Z05330451M1UI2PJW2TSV"
  fqdn               = "${local.public_hostname}.${local.domain_name}"         # FQDN of the public hostname (Ingress)
  gateway_fqdn       = "${local.gateway_hostname}.${local.domain_name}"        # FQDN for Gateway API
}