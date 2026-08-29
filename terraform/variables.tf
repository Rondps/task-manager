variable "cluster_name" {
  description = "Name of the k3d cluster"
  type        = string
  default     = "task-manager-observability"
}

variable "node_count" {
  description = "Number of worker nodes (agents)"
  type        = number
  default     = 1
}

variable "kubeconfig_path" {
  description = "Path to save kubeconfig"
  type        = string
  default     = "./kubeconfig"
}

variable "k3d_wait" {
  description = "Wait for cluster to be ready"
  type        = bool
  default     = true
}