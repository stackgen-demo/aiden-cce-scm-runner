terraform {
  required_version = ">= 1.5"
  required_providers {
    sg = {
      source  = "releases.stackgen.com/stackgen/stackgen"
      version = ">= 0.1.25, < 0.2.0"
    }
  }
}

provider "sg" {
  stackgen_url   = var.stackgen_url
  stackgen_token = var.stackgen_token
  project_id     = var.stackgen_project_id != "" ? var.stackgen_project_id : null
  insecure       = var.stackgen_insecure
}

locals {
  suffix = trimspace(var.name_suffix) == "" ? "" : "-${trimspace(var.name_suffix)}"

  agent_name                  = "${trimspace(var.agent_name)}${local.suffix}"
  default_remote_runner_name  = "cce-scm-runner${local.suffix}"
  resolved_remote_runner_name = trimspace(var.remote_runner_name) != "" ? trimspace(var.remote_runner_name) : local.default_remote_runner_name
  shell_tool_prefix           = local.resolved_remote_runner_name

  describe_skill_name = "scm-describe${local.suffix}"
  analyze_skill_name  = "scm-analyze${local.suffix}"

  gitlab_token_set         = trimspace(var.gitlab_token) != ""
  existing_gitlab_secret   = trimspace(var.existing_gitlab_secret_id) != ""
  create_gitlab_env_secret = local.gitlab_token_set

  gitlab_host = trim(replace(replace(trimspace(var.gitlab_base_url), "https://", ""), "http://", ""), "/")

  gitlab_env_map = merge(
    {
      GITLAB_TOKEN = var.gitlab_token
      GIT_TOKEN    = var.gitlab_token
      GIT_USERNAME = "oauth2"
    },
    trimspace(var.gitlab_base_url) != "" ? {
      GITLAB_BASE_URL = trimspace(var.gitlab_base_url)
      GITLAB_HOST     = local.gitlab_host
      GIT_HOST        = local.gitlab_host
    } : {},
  )

  # Vault requires metadata.value for generic secrets. Runner sync unmarshals GetSecret JSON
  # into env keys — put flat env vars on metadata and keep value as the same JSON blob.
  gitlab_env_metadata = merge(local.gitlab_env_map, {
    value = jsonencode(local.gitlab_env_map)
  })

  # Length must be known at plan time. compact([unknown_id]) makes count unknown on
  # sg_remote_runner_secrets and blocks first apply of gitlab_token.
  runner_generic_secret_ref_ids = (
    local.create_gitlab_env_secret ? [sg_secret.gitlab_runner_env[0].id] :
    local.existing_gitlab_secret ? [trimspace(var.existing_gitlab_secret_id)] :
    []
  )

  bind_runner_secrets = local.create_gitlab_env_secret || local.existing_gitlab_secret

  persona = file("${path.module}/personas/analyst.md")
}

resource "terraform_data" "validate_gitlab_secret_input" {
  lifecycle {
    precondition {
      condition     = !(local.gitlab_token_set && local.existing_gitlab_secret)
      error_message = "Provide gitlab_token or existing_gitlab_secret_id, not both."
    }
  }
}

resource "terraform_data" "validate_model_names" {
  lifecycle {
    precondition {
      condition     = length([for m in var.model_names : m if trimspace(m) != ""]) > 0
      error_message = "model_names must list at least one Guild-registered model name (not an LLM vendor API key). Copy the name from Guild UI → Models."
    }
  }
}

# Flat env secret for mothership → aiden-runner sync. Not a GitLab MCP integration.
resource "sg_secret" "gitlab_runner_env" {
  count = local.create_gitlab_env_secret ? 1 : 0

  name        = "cce-scm-runner-env${local.suffix}"
  description = "GitLab API credentials for ${local.resolved_remote_runner_name} (GITLAB_TOKEN / GIT_TOKEN)."
  category    = "Provider"
  subcategory = "generic"
  metadata    = local.gitlab_env_metadata

  depends_on = [terraform_data.validate_gitlab_secret_input]
}

# Guild registration only. The runner stays Offline until Helm/CLI starts aiden-runner.
resource "sg_remote_runner" "this" {
  count = var.create_remote_runner ? 1 : 0

  name        = local.resolved_remote_runner_name
  description = trimspace(var.remote_runner_description)
  labels      = length(var.remote_runner_labels) > 0 ? var.remote_runner_labels : null

  # aiden-runner writes discovery labels after Online. Treating those as drift
  # recreates the runner and rotates the Helm token.
  lifecycle {
    ignore_changes = [labels]
  }

  depends_on = [terraform_data.validate_gitlab_secret_input]
}

data "sg_remote_runner" "existing" {
  count = var.create_remote_runner ? 0 : 1
  name  = local.resolved_remote_runner_name
}

locals {
  runner_name   = local.resolved_remote_runner_name
  runner_status = var.create_remote_runner ? sg_remote_runner.this[0].status : data.sg_remote_runner.existing[0].status
}

resource "sg_remote_runner_secrets" "this" {
  count = local.bind_runner_secrets ? 1 : 0

  runner_id                     = local.runner_name
  generic_secret_ref_ids        = local.runner_generic_secret_ref_ids
  secrets_sync_interval_seconds = 60
}

resource "sg_runbook_sop" "scm_describe" {
  name    = local.describe_skill_name
  approve = true
  description = trimspace(templatefile("${path.module}/skills/scm-describe.md.tftpl", {
    shell_tool_prefix = local.shell_tool_prefix
  }))
}

resource "sg_runbook_sop" "scm_analyze" {
  name    = local.analyze_skill_name
  approve = true
  description = trimspace(templatefile("${path.module}/skills/scm-analyze.md.tftpl", {
    shell_tool_prefix = local.shell_tool_prefix
  }))
}

resource "sg_agent" "cce_scm_analyst" {
  name = local.agent_name
  # Guild Create currently echoes description as empty; setting a string taints the agent.
  persona     = local.persona
  model_names = [for m in var.model_names : trimspace(m) if trimspace(m) != ""]

  remote_runners = var.remote_runner_attach_to_agent ? toset([local.runner_name]) : null

  hitl = {
    always_allowed = [
      "load_skill",
      "search_skill",
    ]
  }

  auto_approve_tools = var.remote_runner_attach_to_agent && var.auto_approve_runner_tools ? [
    { tool = "${local.shell_tool_prefix}_*" },
  ] : []

  depends_on = [
    sg_remote_runner.this,
    terraform_data.validate_model_names,
    sg_runbook_sop.scm_describe,
    sg_runbook_sop.scm_analyze,
  ]

  # Provider UpdateAgent can 400 on model_names / auto_approve_tools.
  lifecycle {
    ignore_changes = [model_names, auto_approve_tools]
  }
}

resource "sg_agent_budget" "cce_scm_analyst" {
  agent_name  = sg_agent.cce_scm_analyst.name
  limit_usd   = var.agent_budget_usd
  period_type = "daily"
}

resource "sg_policy" "cce_scm_no_write" {
  name        = "cce-scm-no-write${local.suffix}"
  description = "Read-only: block write actions for the CCE SCM analyst."
  type        = "logic"
  rego_source = file("${path.module}/policies/no-write.rego")
}

resource "sg_agent_policy_attachment" "cce_scm_no_write" {
  agent_name = sg_agent.cce_scm_analyst.name
  policy_id  = sg_policy.cce_scm_no_write.id
  enabled    = true
}
