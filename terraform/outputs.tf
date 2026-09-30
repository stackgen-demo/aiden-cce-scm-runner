locals {
  next_steps = <<-EOT

    Aiden CCE SCM stack applied (tofu does not create or attach the remote runner).

      Already done (or do first if bind_gitlab_secret_to_runner=true):
        Guild UI → create remote runner "${local.resolved_remote_runner_name}" → copy token + mothership URL.

      This apply created:
        Agent:              ${sg_agent.cce_scm_analyst.name}  (not attached yet)
        Skills:             ${sg_runbook_sop.scm_describe.name}, ${sg_runbook_sop.scm_analyze.name}
        GitLab integration: ${local.create_gitlab_integration ? local.gitlab_integration_name : "(none)"}
        Secret on runner:   ${nonsensitive(local.bind_runner_secrets)} → ${local.resolved_remote_runner_name}

      Next — hand platform Helm (env only; script does not read tofu state):
        export MOTHERSHIP_URL="${var.stackgen_url}"
        export STACKGEN_RUNNER_TOKEN="<registration-token-from-Guild-UI>"
        export RUNNER_IMAGE=${var.runner_docker_image}
        ./helm/install.sh

      Then — Guild UI: attach ${local.resolved_remote_runner_name} → ${sg_agent.cce_scm_analyst.name}
        Wait ~60s for vault sync, then chat the demo prompt.

  EOT
}

output "next_steps" {
  description = "Manual runner → Helm → attach → chat."
  value       = local.next_steps
}

output "agent_name" {
  description = "Persona agent (identity only). Attach the remote runner in Guild UI after Online."
  value       = sg_agent.cce_scm_analyst.name
}

output "describe_skill_name" {
  description = "Approved Guild skill: cce scm describe (API-first, no clone)."
  value       = sg_runbook_sop.scm_describe.name
}

output "analyze_skill_name" {
  description = "Approved Guild skill: clone then cce --folder (deep scan, last resort)."
  value       = sg_runbook_sop.scm_analyze.name
}

output "remote_runner_name" {
  description = "Expected Guild remote runner name (create manually; not managed by this root)."
  value       = local.resolved_remote_runner_name
}

output "gitlab_integration_name" {
  description = "Guild GitLab integration name (empty when not created)."
  value       = local.create_gitlab_integration ? local.gitlab_integration_name : ""
}

output "gitlab_secret_bound" {
  description = "True when this apply binds the GitLab vault secret on remote_runner_name."
  value       = nonsensitive(local.bind_runner_secrets)
}

output "runner_docker_image" {
  description = "CCE overlay image for Helm RUNNER_IMAGE."
  value       = var.runner_docker_image
}

output "helm_env_example" {
  description = "Env vars platform must set before ./helm/install.sh (token from Guild UI, not tofu)."
  value       = <<-EOT
    export MOTHERSHIP_URL="${var.stackgen_url}"
    export STACKGEN_RUNNER_TOKEN="<from Guild → remote runner → registration token>"
    export RUNNER_IMAGE="${var.runner_docker_image}"
    # optional: export NS=aiden-cce-runner RUNNER_NAME=${local.resolved_remote_runner_name}
    ./helm/install.sh
  EOT
}

output "demo_prompt" {
  description = "Prompt-only API metadata example (user does not clone)."
  value       = "Describe https://gitlab.com/gitlab-org/cli as repository metadata YAML. Use cce scm describe. Do not clone."
}
