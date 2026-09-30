variable "stackgen_url" {
  description = "Base URL of your Guild / Aiden tenant (no trailing slash). Set via TF_VAR_stackgen_url."
  type        = string
}

variable "stackgen_insecure" {
  description = "Allow plaintext HTTP to Guild (local development only)."
  type        = bool
  default     = false
}

variable "stackgen_token" {
  description = "Guild personal access token used by tofu to create agents, integrations, and secrets. Set via TF_VAR_stackgen_token. Omit from tfvars rather than setting an empty string."
  type        = string
  sensitive   = true
}

variable "stackgen_project_id" {
  description = "Optional Guild org / project ID when the tenant requires explicit scope. Set via TF_VAR_stackgen_project_id when needed."
  type        = string
  default     = ""
}

variable "agent_name" {
  description = "Guild agent name for the CCE SCM analyst persona."
  type        = string
  default     = "cce-scm-analyst"
}

variable "agent_budget_usd" {
  description = "Daily USD budget for the analyst agent."
  type        = number
  default     = 10
}

variable "remote_runner_name" {
  description = <<-EOT
    Name of the Guild remote runner you create manually (UI/API). Not created by this root.
    Used for shell-tool prefixes and optional vault secret binding.
    Empty uses cce-scm-runner (+ optional name_suffix).
  EOT
  type        = string
  default     = ""
}

variable "auto_approve_runner_tools" {
  description = "Auto-approve <remote_runner_name>_execute_* tools so scm describe is not HITL-gated after you attach the runner in Guild."
  type        = bool
  default     = true
}

variable "create_gitlab_integration" {
  description = "When true (default), create sg_guild_integration type=gitlab and its vault secret."
  type        = bool
  default     = true
}

variable "bind_gitlab_secret_to_runner" {
  description = <<-EOT
    When true (default), bind the GitLab vault secret on the manually created remote runner
    (typed_secret_refs.gitlab) so mothership sync injects GITLAB_TOKEN after Online.
    The runner named by remote_runner_name must already exist in Guild.
    Set false if you will bind the secret in Guild UI instead.
  EOT
  type        = bool
  default     = true
}

variable "gitlab_integration_name" {
  description = "Guild GitLab integration name. Empty uses cce-scm-gitlab (+ optional name_suffix)."
  type        = string
  default     = ""
}

variable "gitlab_integration_image" {
  description = "Container image for the Guild GitLab integration."
  type        = string
  default     = "ghcr.io/appcd-dev/stackgen-guild-integration-gitlab:main"
}

variable "gitlab_token" {
  description = <<-EOT
    GitLab PAT (read_api or api). Set via TF_VAR_gitlab_token.
    Stored as vault metadata key `token` (SCM/gitlab). Vault Resolve also emits
    GITLAB_TOKEN for runner sync. Omit from tfvars rather than setting "".
  EOT
  type        = string
  sensitive   = true
  default     = ""
}

variable "gitlab_base_url" {
  description = "GitLab origin. Default https://gitlab.com. Stored as vault metadata GITLAB_API_URL."
  type        = string
  default     = "https://gitlab.com"
}

variable "existing_gitlab_secret_id" {
  description = "Optional pre-created sg_secret UUID (SCM/gitlab; metadata must include `token`). Mutually exclusive with gitlab_token."
  type        = string
  default     = ""
}

variable "runner_docker_image" {
  description = "CCE overlay image for Helm notes. Default is the public stackgen-demo package."
  type        = string
  default     = "ghcr.io/stackgen-demo/aiden-cce-scm-runner:scm-main"
}

variable "name_suffix" {
  description = "Optional suffix appended with a leading hyphen to the agent, runner default name, and vault secret."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]*$", var.name_suffix))
    error_message = "name_suffix must be empty or contain only letters, digits, and hyphens."
  }
}
