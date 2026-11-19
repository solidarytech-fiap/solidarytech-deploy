# Alertas como codigo (Datadog): monitores APM, Watchdog (AIOps), SLOs e o
# webhook de self-healing. Ciclo de incidente completo em docs/itsm.md
# (repo solidarytech-app).

locals {
  services = ["ngo-service", "donation-service", "volunteer-service"]
  op       = var.trace_operation
  tags     = ["project:solidarytech", "env:${var.env}", "team:ngo-core", "managed-by:terraform"]

  notify = join("\n", compact([
    "@${var.incident_handle}",
    var.slack_handle != "" ? "@${var.slack_handle}" : "",
  ]))

  runbook = "https://github.com/solidarytech-fiap/solidarytech-app/blob/main/docs/runbooks"
}

# ------------------------------------------------------------------
# 1. Taxa de erros 5xx por servico -> JSM + Slack + self-healing
# ------------------------------------------------------------------
resource "datadog_monitor" "error_rate" {
  for_each = toset(local.services)

  name     = "[SolidaryTech] ${each.key} - erros 5xx > ${var.error_rate_threshold}%"
  type     = "query alert"
  priority = each.key == "donation-service" ? 1 : 2

  query = "sum(last_5m):default_zero(100 * sum:trace.${local.op}.errors{service:${each.key},env:${var.env}}.as_count() / sum:trace.${local.op}.hits{service:${each.key},env:${var.env}}.as_count()) > ${var.error_rate_threshold}"

  message = <<-EOT
    {{#is_alert}}
    ## {{service.name}} com {{value}}% de erros 5xx (limite ${var.error_rate_threshold}%)
    **Severidade:** ${each.key == "donation-service" ? "SEV1 - doacoes impactadas" : "SEV2"}
    **Diagnostico:** APM > Services > {{service.name}} > Traces com erro; Logs `service:{{service.name}} status:error`.
    **Runbook:** ${local.runbook}/service-high-error-rate.md
    **Automacao:** self-healing (rollout restart) disparado via GitHub Actions.
    ${local.notify}
    @webhook-solidarytech-self-healing
    {{/is_alert}}
    {{#is_recovery}}
    {{service.name}} recuperado. Registrar MTTR no incidente e avaliar post-mortem.
    ${local.notify}
    {{/is_recovery}}
  EOT

  monitor_thresholds {
    critical = var.error_rate_threshold
    warning  = var.error_rate_threshold * 0.6
  }

  require_full_window = false
  notify_no_data      = false
  renotify_interval   = 30
  evaluation_delay    = 60
  include_tags        = true
  tags                = concat(local.tags, ["service:${each.key}", "severity:critical"])
}

# ------------------------------------------------------------------
# 2. Latencia media do donation-service (limiar do SLI = 300ms)
# ------------------------------------------------------------------
resource "datadog_monitor" "donation_latency" {
  name     = "[SolidaryTech] donation-service - latencia media > 300ms"
  type     = "query alert"
  priority = 2

  query = "avg(last_10m):sum:trace.${local.op}.duration{service:donation-service,env:${var.env}}.as_count() / sum:trace.${local.op}.hits{service:donation-service,env:${var.env}}.as_count() > 0.3"

  message = <<-EOT
    donation-service lento ({{value}}s em media). Verificar RDS (conexoes, CPU) e saturacao dos pods (HPA).
    Runbook: ${local.runbook}/donation-slo-burn.md
    ${local.notify}
  EOT

  monitor_thresholds {
    critical = 0.3
    warning  = 0.2
  }

  require_full_window = false
  tags                = concat(local.tags, ["service:donation-service", "severity:warning"])
}

# ------------------------------------------------------------------
# 3. AIOps - Watchdog: anomalias detectadas automaticamente por ML
#    (latencia, erros, trafego) nos servicos do APM.
# ------------------------------------------------------------------
resource "datadog_monitor" "watchdog" {
  name = "[SolidaryTech] Watchdog - anomalia detectada (AIOps)"
  type = "event-v2 alert"

  query = "events(\"source:watchdog story_category:apm env:${var.env}\").rollup(\"count\").by(\"story_key,service\").last(\"30m\") > 0"

  message = <<-EOT
    ## Watchdog detectou comportamento anomalo em {{service.name}}
    Deteccao preditiva: a anomalia foi identificada antes de violar o SLO.
    Abrir a story no Watchdog para ver causa provavel (Root Cause Analysis).
    ${local.notify}
  EOT

  monitor_thresholds {
    critical = 0
  }

  tags = concat(local.tags, ["severity:warning", "aiops:watchdog"])
}

# ------------------------------------------------------------------
# 4. SLOs no Datadog (espelham os do Prometheus - docs/sre.md)
# ------------------------------------------------------------------
resource "datadog_service_level_objective" "donation_availability" {
  name        = "donation-service - Disponibilidade"
  type        = "metric"
  description = "Requisicoes ao donation-service sem erro / total. SLA externo com as ONGs: 99,5%."

  query {
    numerator   = "sum:trace.${local.op}.hits{service:donation-service,env:${var.env}}.as_count() - sum:trace.${local.op}.errors{service:donation-service,env:${var.env}}.as_count()"
    denominator = "sum:trace.${local.op}.hits{service:donation-service,env:${var.env}}.as_count()"
  }

  thresholds {
    timeframe = "30d"
    target    = 99.9
    warning   = 99.95
  }

  thresholds {
    timeframe = "7d"
    target    = 99.9
    warning   = 99.95
  }

  tags = concat(local.tags, ["service:donation-service", "sli:availability"])
}

resource "datadog_service_level_objective" "donation_latency" {
  name        = "donation-service - Latencia (fatias de 5 min com media < 300ms)"
  type        = "time_slice"
  description = "Proporcao de intervalos de 5 minutos com latencia media abaixo de 300ms."

  sli_specification {
    time_slice {
      comparator = "<"
      threshold  = 0.3
      query {
        formula {
          formula_expression = "query1 / query2"
        }
        query {
          metric_query {
            name  = "query1"
            query = "sum:trace.${local.op}.duration{service:donation-service,env:${var.env}}.as_count()"
          }
        }
        query {
          metric_query {
            name  = "query2"
            query = "sum:trace.${local.op}.hits{service:donation-service,env:${var.env}}.as_count()"
          }
        }
      }
      query_interval_seconds = 300
    }
  }

  thresholds {
    timeframe = "30d"
    target    = 95
    warning   = 97
  }

  tags = concat(local.tags, ["service:donation-service", "sli:latency"])
}

# Alerta de queima de error budget no proprio Datadog.
resource "datadog_monitor" "donation_slo_burn" {
  name = "[SolidaryTech] donation-service - SLO disponibilidade: burn rate alto"
  type = "slo alert"

  query = "burn_rate(\"${datadog_service_level_objective.donation_availability.id}\").over(\"30d\").long_window(\"1h\").short_window(\"5m\") > 14.4"

  message = <<-EOT
    Error budget do donation-service sendo consumido 14,4x mais rapido que o sustentavel
    (2% do budget mensal em 1h). Runbook: ${local.runbook}/donation-slo-burn.md
    ${local.notify}
  EOT

  monitor_thresholds {
    critical = 14.4
  }

  tags = concat(local.tags, ["service:donation-service", "severity:critical"])
}

# ------------------------------------------------------------------
# 5. Webhook -> GitHub repository_dispatch -> workflow self-healing.yml
# ------------------------------------------------------------------
resource "datadog_webhook" "self_healing" {
  name      = "solidarytech-self-healing"
  url       = "https://api.github.com/repos/${var.github_repo}/dispatches"
  encode_as = "json"

  payload = jsonencode({
    event_type = "datadog-alert"
    client_payload = {
      service    = "$TAGS[service]"
      alert_name = "$ALERT_TITLE"
      alert_url  = "$LINK"
      alert_id   = "$ALERT_ID"
      transition = "$ALERT_TRANSITION"
    }
  })

  custom_headers = jsonencode({
    "Accept"               = "application/vnd.github+json"
    "Authorization"        = "Bearer ${data.aws_ssm_parameter.github_pat.value}"
    "X-GitHub-Api-Version" = "2022-11-28"
  })
}

# ------------------------------------------------------------------
# 6. Dashboard executivo de SLO no Datadog
# ------------------------------------------------------------------
resource "datadog_dashboard" "sre" {
  title       = "SolidaryTech - SRE (SLOs e Error Budget)"
  layout_type = "ordered"
  description = "Painel exclusivo de SLOs do donation-service. Gerenciado por Terraform."

  widget {
    service_level_objective_definition {
      title             = "Disponibilidade (99,9%)"
      view_type         = "detail"
      slo_id            = datadog_service_level_objective.donation_availability.id
      show_error_budget = true
      view_mode         = "overall"
      time_windows      = ["7d", "30d"]
    }
  }

  widget {
    service_level_objective_definition {
      title             = "Latencia (95% < 300ms)"
      view_type         = "detail"
      slo_id            = datadog_service_level_objective.donation_latency.id
      show_error_budget = true
      view_mode         = "overall"
      time_windows      = ["30d"]
    }
  }

  widget {
    manage_status_definition {
      title          = "Monitores SolidaryTech"
      query          = "tag:project:solidarytech"
      display_format = "countsAndList"
      sort           = "status,asc"
    }
  }
}

output "slo_ids" {
  value = {
    availability = datadog_service_level_objective.donation_availability.id
    latency      = datadog_service_level_objective.donation_latency.id
  }
}

output "dashboard_url" {
  value = datadog_dashboard.sre.url
}
