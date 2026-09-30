locals {
  next_steps = <<-EOT

    Aiden CCE SCM stack applied (no remote runner created by tofu).

      1. Guild:                      ${var.stackgen_url}
      2. Agent (no runner attached): ${sg_agent.cce_scm_analyst.name}
         skill (default):            ${sg_runbook_sop.scm_describe.name}
         skill (deep, gated):        ${sg_runbook_sop.scm_analyze.name}
      3. GitLab integration:         ${local.create_gitlab_integration ? local.gitlab_integration_name : "(none)"}
         Secret bind on runner:      ${nonsensitive(local.bind_runner_secrets)} → ${local.resolved_remote_runner_name}
         (Runner must already exist when bind_gitlab_secret_to_runner=true.)
      4. Create remote runner in Guild UI (manual). Name it: ${local.resolved_remote_runner_name}
         Copy the registration token + mothership URL.
      5. Hand platform Helm (they set env; script does not read tofu state):
           export MOTHERSHIP_URL="<guild-url>"
           export STACKGEN_RUNNER_TOKEN="<token-from-step-4>"
           export RUNNER_IMAGE=${var.runner_docker_image}
           ./helm/install.sh
      6. When Online: attach ${local.resolved_remote_runner_name} to agent ${sg_agent.cce_scm_analyst.name} in Guild UI.
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
