output "cluster_name" {
  description = "Name of the created cluster"
  value       = var.cluster_name
}

output "kubeconfig_path" {
  description = "Path to kubeconfig file"
  value       = var.kubeconfig_path
}

output "commands" {
  description = "Useful commands after deployment"
  value = {
    get_nodes    = "kubectl get nodes"
    get_pods     = "kubectl get pods -A"
    port_forward = "kubectl port-forward service/task-manager-service 8080:8080"
    grafana      = "http://localhost:3000"
    prometheus   = "http://localhost:9090"
  }
}