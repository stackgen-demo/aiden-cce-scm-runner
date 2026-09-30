locals {
  next_steps = <<-EOT

    Aiden CCE SCM runner applied (API-first).

      1. Open Guild:              ${var.stackgen_url}
      2. Agent:                   ${sg_agent.cce_scm_analyst.name}
         skill (default):         ${sg_runbook_sop.scm_describe.name} (cce scm describe, no clone)
         skill (deep, gated):     ${sg_runbook_sop.scm_analyze.name} (clone + cce --folder)
         remote_runner_attach_to_agent=${var.remote_runner_attach_to_agent}${var.remote_runner_attach_to_agent ? " (runner bound on sg_agent)" : " (not bound)"}
      3. Runner:                  ${local.runner_name}  status=${local.runner_status}
         GitLab vault bound:      ${nonsensitive(local.bind_runner_secrets)}
      4. Deploy aiden-runner (public image; no GHCR login):
           cd .. && ./helm/install.sh
         Or set RUNNER_IMAGE=${var.runner_docker_image} explicitly.
      5. When Guild shows the runner Online and gitlab_token is set, wait ~60s for vault sync.
         Then chat: Describe https://gitlab.com/gitlab-org/cli as repository metadata. Prefer the forge/API path.
         If attach was false: ./scripts/attach-runner.sh

  EOT
}

output "next_steps" {
  description = "Copy-paste steps after apply: Helm, wait Online, chat."
  value       = local.next_steps
}

output "agent_name" {
  description = "Persona agent (identity only). Default procedure is skill scm-describe."
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

output "model_names" {
  description = "Guild model names wired on the agent (existing tenant models)."
  value       = [for m in var.model_names : trimspace(m) if trimspace(m) != ""]
}

output "remote_runner_name" {
  value = local.runner_name
}

output "remote_runner_status" {
  description = "Guild runner lifecycle status. Attach the agent only when this is Online."
  value       = local.runner_status
}

output "remote_runner_attach_to_agent" {
  value = var.remote_runner_attach_to_agent
}

output "gitlab_secret_bound" {
  description = "True when a generic GITLAB_TOKEN vault secret is bound on the runner."
  value       = nonsensitive(local.bind_runner_secrets)
}

output "runner_docker_image" {
  description = "CCE overlay image for Helm."
  value       = var.runner_docker_image
}

output "remote_runner_mothership_url" {
  description = "Mothership URL for Helm runner.mothershipUrl."
  value       = var.create_remote_runner ? sg_remote_runner.this[0].mothership_url : ""
}

output "remote_runner_token" {
  description = "Runner registration token for Helm runner.token. Not the GitLab PAT."
  value       = var.create_remote_runner ? sg_remote_runner.this[0].token : null
  sensitive   = true
}

output "remote_runner_helm_install_command" {
  description = "Provider stock Helm string (wrong image/namespace). Prefer ../helm/install.sh."
  value       = var.create_remote_runner ? sg_remote_runner.this[0].helm_install_command : null
  sensitive   = true
}

output "demo_prompt" {
  description = "Prompt-only API metadata example (user does not clone)."
  value       = "Describe https://gitlab.com/gitlab-org/cli as repository metadata YAML. Use cce scm describe. Do not clone."
}
