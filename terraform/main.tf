terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12" # provider oficial do Terraform para instalar Helm charts
    }
  }
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path # onde o Terraform vai buscar as credenciais
  }                                   # do cluster (geradas mais abaixo)
}

# Primeiro recurso: cria o cluster k3d. Repare que NÃO existe um provider nativo
# de k3d — o Terraform está apenas orquestrando comandos de shell (local-exec),
# não gerenciando o cluster de forma verdadeiramente declarativa
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
    when        = destroy # este bloco só roda em "terraform destroy"
    command     = "k3d cluster delete ${self.triggers.cluster_name}"
    interpreter = ["bash", "-c"]
  }

  triggers = {
    cluster_name = var.cluster_name
    node_count   = var.node_count
  }
}

# Aplica os manifests Kubernetes do diretório k8s/ do repositório
resource "null_resource" "deploy_app" {
  depends_on = [null_resource.k3d_cluster]
  provisioner "local-exec" {
    command = "kubectl --kubeconfig=${var.kubeconfig_path} apply -f ${path.module}/../k8s/namespace.yaml && kubectl --kubeconfig=${var.kubeconfig_path} apply -f ${path.module}/../k8s/"
  }
  triggers = { always_run = timestamp() }
}

# Stack de observabilidade via Helm — a mesma que vamos explorar no Bloco 4
resource "helm_release" "kube_prometheus_stack" {
  depends_on       = [null_resource.deploy_app]
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack" # Prometheus + Grafana, prontos e configurados
  namespace        = "monitoring"
  create_namespace = true
}

resource "helm_release" "loki_stack" {
  depends_on = [null_resource.deploy_app, helm_release.kube_prometheus_stack]
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack" # Loki + Promtail
  namespace  = "monitoring"

  set {
    name  = "promtail.enabled"
    value = "true"
  }
  set {
    name  = "grafana.enabled"
    value = "false" # evita subir um SEGUNDO Grafana — já temos um vindo
  }

  # Prometheus permanece como datasource padrão
  set {
    name  = "loki.isDefault"
    value = "false"
  }

  # Não provisionar Loki automaticamente no Grafana.
  # A atividade pede para adicioná-lo manualmente.
  set {
    name  = "grafana.sidecar.datasources.enabled"
    value = "false"
  }

  # Corrige incompatibilidade do Loki antigo do loki-stack
  set {
    name  = "loki.image.tag"
    value = "2.9.3"
  }
} # do kube-prometheus-stack acima