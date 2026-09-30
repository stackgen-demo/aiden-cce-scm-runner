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
  description = "Guild personal access token used by tofu to create runners, agents, and secrets. Set via TF_VAR_stackgen_token. Omit from tfvars rather than setting an empty string."
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

variable "create_remote_runner" {
  description = "Register a new sg_remote_runner (token + mothership). Set false to look up remote_runner_name."
  type        = bool
  default     = true
}

variable "remote_runner_name" {
  description = "Guild remote runner name. Empty uses cce-scm-runner (+ optional name_suffix)."
  type        = string
  default     = ""
}

variable "remote_runner_description" {
  description = "Description stored on sg_remote_runner when create_remote_runner is true."
  type        = string
  default     = "CCE SCM runner (cce scm describe API-first; clone only for deep scan)."
}

variable "remote_runner_labels" {
  description = "Optional static labels on the runner. Do not use timestamp() — it re-registers the runner on every apply."
  type        = map(string)
  default     = {}
}

variable "remote_runner_attach_to_agent" {
  description = <<-EOT
    When true (default), sets sg_agent.remote_runners to this runner on the same apply that
    registers sg_remote_runner. Guild allows attach while the runner is still Offline; shell
    tools work only after Helm/CLI brings the runner Online.
  EOT
  type        = bool
  default     = true
}

variable "auto_approve_runner_tools" {
  description = "When the runner is attached, auto-approve <runner>_execute_* tools so scm describe is not HITL-gated."
  type        = bool
  default     = true
}

variable "create_gitlab_integration" {
  description = "When true (default), create sg_guild_integration type=gitlab and bind its vault secret on the remote runner (typed_secret_refs.gitlab)."
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
    GitLab PAT (read_api). Set via TF_VAR_gitlab_token.
    Creates an SCM/gitlab vault secret used by sg_guild_integration and bound on
    the remote runner so sync injects GITLAB_TOKEN for cce scm describe.
    Omit from tfvars rather than setting "".
  EOT
  type        = string
  sensitive   = true
  default     = ""
}

variable "gitlab_base_url" {
  description = "GitLab origin. Default https://gitlab.com. Stored on the integration vault secret and synced as GITLAB_BASE_URL / GITLAB_HOST on the runner."
  type        = string
  default     = "https://gitlab.com"
}

variable "existing_gitlab_secret_id" {
  description = "Optional pre-created sg_secret UUID (SCM/gitlab; should include private_token/base_url and preferably GITLAB_TOKEN). Mutually exclusive with gitlab_token. Used for the integration and runner typed bind."
  type        = string
  default     = ""
}

variable "runner_docker_image" {
  description = "CCE overlay image for Helm/Docker notes. Default is the public stackgen-demo package."
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
