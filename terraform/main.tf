terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

resource "null_resource" "k3d_cluster" {
  provisioner "local-exec" {
    command     = <<EOT
      #!/bin/bash
      set -e
      CLUSTER_NAME="${var.cluster_name}"
      NODE_COUNT="${var.node_count}"
      CMD="k3d cluster create $CLUSTER_NAME --servers 1 --agents $NODE_COUNT --port 8081:80@loadbalancer"
      if [ "${var.k3d_wait}" = "true" ]; then
        CMD="$CMD --wait"
      fi
      $CMD
      k3d kubeconfig get $CLUSTER_NAME > ${var.kubeconfig_path}
    EOT
    interpreter = ["bash", "-c"]
  }

  provisioner "local-exec" {
    when        = destroy
    command     = "k3d cluster delete ${self.triggers.cluster_name}"
    interpreter = ["bash", "-c"]
  }

  triggers = {
    cluster_name = var.cluster_name
    node_count   = var.node_count
  }
}

resource "null_resource" "deploy_app" {
  depends_on = [null_resource.k3d_cluster]
  provisioner "local-exec" {
    command = "kubectl --kubeconfig=${var.kubeconfig_path} apply -f ${path.module}/../k8s/namespace.yaml && kubectl --kubeconfig=${var.kubeconfig_path} apply -f ${path.module}/../k8s/"
  }
  triggers = { always_run = timestamp() }
}

resource "helm_release" "kube_prometheus_stack" {
  depends_on       = [null_resource.deploy_app]
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
}

resource "helm_release" "loki_stack" {
  depends_on = [null_resource.deploy_app, helm_release.kube_prometheus_stack]
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  namespace  = "monitoring"

  set {
    name  = "promtail.enabled"
    value = "true"
  }
  set {
    name  = "grafana.enabled"
    value = "false"
  }
  set {
    name  = "loki.isDefault"
    value = "false"
  }
  set {
    name  = "grafana.sidecar.datasources.enabled"
    value = "false"
  }
  set {
    name  = "loki.image.tag"
    value = "2.9.3"
  }
}