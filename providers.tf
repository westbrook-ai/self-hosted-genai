provider "aws" {
  profile = "di"
  region  = "us-west-2"
}

provider "helm" {
  kubernetes = {
    host                   = module.open-webui-eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.open-webui-eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--output", "json"]
    }
  }
}

provider "kubernetes" {
  host                   = module.open-webui-eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.open-webui-eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--output", "json"]
  }
}

provider "kubectl" {
  host                   = module.open-webui-eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.open-webui-eks.cluster_certificate_authority_data)
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name, "--output", "json"]
  }
}