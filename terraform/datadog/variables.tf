variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "datadog_site" {
  type    = string
  default = "datadoghq.com"
}

variable "env" {
  type    = string
  default = "prod"
}

variable "trace_operation" {
  description = <<-EOT
    Nome da operacao dos spans HTTP server no Datadog (prefixo das metricas
    trace.<operation>.hits/errors/duration). Confirme em Metrics > Explorer
    buscando "trace." + service:donation-service. Valores comuns com OTel:
    "http.server.request" (padrao atual) ou "http.request".
  EOT
  type        = string
  default     = "http.server.request"
}

variable "incident_handle" {
  description = "Handle da integracao Jira Service Management no Datadog (sem @)"
  type        = string
  default     = "jsm-solidarytech"
}

variable "slack_handle" {
  description = "Handle do canal Slack no Datadog (sem @). Vazio = desligado."
  type        = string
  default     = "slack-solidarytech-alerts"
}

variable "github_repo" {
  description = "Repo que recebe o repository_dispatch do self-healing"
  type        = string
  default     = "solidarytech-fiap/solidarytech-deploy"
}

variable "error_rate_threshold" {
  description = "Critical do monitor de 5xx (%)"
  type        = number
  default     = 5
}
