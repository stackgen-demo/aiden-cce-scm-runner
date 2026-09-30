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

  gitlab_integration_name = trimspace(var.gitlab_integration_name) != "" ? trimspace(var.gitlab_integration_name) : "cce-scm-gitlab${local.suffix}"

  gitlab_token_set          = trimspace(var.gitlab_token) != ""
  existing_gitlab_secret    = trimspace(var.existing_gitlab_secret_id) != ""
  create_gitlab_secret      = local.gitlab_token_set
  create_gitlab_integration = var.create_gitlab_integration && (local.create_gitlab_secret || local.existing_gitlab_secret)

  gitlab_base_url = trimspace(var.gitlab_base_url) != "" ? trimspace(var.gitlab_base_url) : "https://gitlab.com"

  gitlab_secret_metadata = {
    token          = var.gitlab_token
    GITLAB_API_URL = local.gitlab_base_url
  }

  gitlab_secret_id = (
    local.create_gitlab_secret ? sg_secret.gitlab_vault[0].id :
    local.existing_gitlab_secret ? trimspace(var.existing_gitlab_secret_id) :
    ""
  )

  bind_runner_secrets = local.create_gitlab_integration

  persona = file("${path.module}/personas/analyst.md")
}

resource "terraform_data" "validate_gitlab_input" {
  lifecycle {
    precondition {
      condition     = !(local.gitlab_token_set && local.existing_gitlab_secret)
      error_message = "Provide gitlab_token or existing_gitlab_secret_id, not both."
    }
    precondition {
      condition     = !var.create_gitlab_integration || local.gitlab_token_set || local.existing_gitlab_secret
      error_message = "create_gitlab_integration requires gitlab_token or existing_gitlab_secret_id."
    }
  }
}

# Vault secret for the GitLab Guild integration. Same UUID is bound on the remote
# runner via typed_secret_refs.gitlab so mothership sync injects env (incl. GITLAB_TOKEN).
resource "sg_secret" "gitlab_vault" {
  count = local.create_gitlab_secret ? 1 : 0

  name        = "${local.gitlab_integration_name}-vault"
  description = "GitLab credentials for ${local.gitlab_integration_name} (integration + runner env sync)."
  category    = "SCM"
  subcategory = "gitlab"
  metadata    = local.gitlab_secret_metadata

  depends_on = [terraform_data.validate_gitlab_input]
}

resource "sg_guild_integration" "gitlab" {
  count = local.create_gitlab_integration ? 1 : 0

  name           = local.gitlab_integration_name
  description    = "GitLab SCM integration for ${local.resolved_remote_runner_name}."
  type           = "gitlab"
  scope          = "PROJECT"
  secret_ref_ids = [local.gitlab_secret_id]
  enabled        = true

  image = {
    name = var.gitlab_integration_image
  }

  depends_on = [
    terraform_data.validate_gitlab_input,
    sg_secret.gitlab_vault,
  ]
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

  depends_on = [terraform_data.validate_gitlab_input]
}

data "sg_remote_runner" "existing" {
  count = var.create_remote_runner ? 0 : 1
  name  = local.resolved_remote_runner_name
}

locals {
  runner_name   = local.resolved_remote_runner_name
  runner_status = var.create_remote_runner ? sg_remote_runner.this[0].status : data.sg_remote_runner.existing[0].status
}

# Attach the GitLab integration vault secret to the remote runner (typed gitlab slot).
resource "sg_remote_runner_secrets" "this" {
  count = local.bind_runner_secrets ? 1 : 0

  runner_id = local.runner_name
  typed_secret_refs = {
    gitlab = local.gitlab_secret_id
  }
  generic_secret_ref_ids        = []
  secrets_sync_interval_seconds = 60

  depends_on = [
    sg_remote_runner.this,
    sg_guild_integration.gitlab,
    sg_secret.gitlab_vault,
  ]
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
  # No model_names — this root does not create or attach LLM providers/models.
  persona = local.persona

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
    sg_runbook_sop.scm_describe,
    sg_runbook_sop.scm_analyze,
  ]

  # Provider UpdateAgent can 400 on auto_approve_tools (when_args_contain).
  lifecycle {
    ignore_changes = [auto_approve_tools]
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
