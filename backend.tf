terraform {
  backend "local" {}
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
  #   Update and uncomment block below if storing state in S3 
  #   backend "s3" {
  #     bucket = "your-bucket"
  #     key = "terraform/ollama"
  #     region = "your-region"
  #   }
}