# Gateway API resources for Open WebUI
# This provides an alternative to the existing Ingress-based approach using the newer Gateway API

# GatewayClass defines the ALB controller as the implementation
resource "kubectl_manifest" "gateway_class" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: GatewayClass
    metadata:
      name: aws-alb
    spec:
      controllerName: gateway.k8s.aws/alb
  YAML

  depends_on = [
    helm_release.aws_load_balancer_controller,
    null_resource.gateway_api_crds,
    null_resource.lbc_gateway_crds
  ]
}

# LoadBalancerConfiguration defines ALB-specific settings (replaces Ingress annotations)
resource "kubectl_manifest" "open_webui_lb_config" {
  yaml_body = <<-YAML
    apiVersion: gateway.k8s.aws/v1beta1
    kind: LoadBalancerConfiguration
    metadata:
      name: open-webui-gateway-lb-config
      namespace: genai
    spec:
      loadBalancerName: open-webui-gateway-alb
      scheme: internet-facing
      securityGroups:
        - ${aws_security_group.open-webui-ingress-sg.id}
      listenerConfigurations:
        - protocolPort: HTTPS:443
          defaultCertificate: "${aws_acm_certificate.gateway.arn}"
  YAML

  depends_on = [
    kubectl_manifest.gateway_class,
    aws_acm_certificate_validation.gateway,
    helm_release.open_webui
  ]
}

# TargetGroupConfiguration defines how traffic is routed to pods
resource "kubectl_manifest" "open_webui_tg_config" {
  yaml_body = <<-YAML
    apiVersion: gateway.k8s.aws/v1beta1
    kind: TargetGroupConfiguration
    metadata:
      name: open-webui-gateway-tg-config
      namespace: genai
    spec:
      targetReference:
        kind: Service
        name: open-webui
      defaultConfiguration:
        targetType: ip
  YAML

  depends_on = [
    kubectl_manifest.gateway_class,
    helm_release.open_webui
  ]
}

# Gateway resource (replaces Ingress) - creates the ALB
resource "kubectl_manifest" "open_webui_gateway" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: open-webui-gateway
      namespace: genai
      annotations:
        # External DNS will create DNS record for this hostname
        external-dns.alpha.kubernetes.io/hostname: "${local.gateway_fqdn}"
    spec:
      gatewayClassName: aws-alb
      infrastructure:
        parametersRef:
          kind: LoadBalancerConfiguration
          name: open-webui-gateway-lb-config
          group: gateway.k8s.aws
      listeners:
        - name: https
          protocol: HTTPS
          port: 443
          hostname: "${local.gateway_fqdn}"
          allowedRoutes:
            namespaces:
              from: Same
  YAML

  depends_on = [
    kubectl_manifest.open_webui_lb_config,
    kubectl_manifest.open_webui_tg_config
  ]
}

# HTTPRoute is now managed by the Open WebUI Helm chart when route.enabled=true
# See test-gateway-values.yaml for the configuration used during testing
