locals {
  next_steps = <<-EOT

    Aiden CCE SCM stack applied (tofu does not create or attach the remote runner).

      Already done:
        Guild UI → create remote runner "${local.resolved_remote_runner_name}" → copy token + mothership URL.

      This apply created:
        Agent:              ${sg_agent.cce_scm_analyst.name}  (not attached yet)
        Skill:              ${sg_skill.scm_api_to_backstage.name}  (sg_skill; bound on agent.skills)
        GitLab integration: ${local.create_gitlab_integration ? local.gitlab_integration_name : "(none)"}

      Next — hand platform Helm (env only; script does not read tofu state):
        export MOTHERSHIP_URL="${var.stackgen_url}"
        export STACKGEN_RUNNER_TOKEN="<registration-token-from-Guild-UI>"
        export RUNNER_IMAGE=${var.runner_docker_image}
        ./helm/install.sh

      Then — Guild UI:
        1. Bind the GitLab vault secret onto ${local.resolved_remote_runner_name} (if using GitLab)
        2. Attach ${local.resolved_remote_runner_name} → ${sg_agent.cce_scm_analyst.name}
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

output "skill_name" {
  description = "Guild catalog skill: API scan → customer Backstage YAML (SKILL.md via sg_skill)."
  value       = sg_skill.scm_api_to_backstage.name
}

output "remote_runner_name" {
  description = "Expected Guild remote runner name (create manually; not managed by this root)."
  value       = local.resolved_remote_runner_name
}

output "gitlab_integration_name" {
  description = "Guild GitLab integration name (empty when not created)."
  value       = local.create_gitlab_integration ? local.gitlab_integration_name : ""
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
  description = "API scan → Backstage YAML demo (no clone; no upload unless customer names a destination)."
  value       = "Scan https://gitlab.com/gitlab-org/cli via SCM APIs and produce Backstage catalog YAML. Use the customer template if I paste one; otherwise use the skill example template. Do not clone. Do not upload anywhere."
}
