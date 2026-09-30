variable "stackgen_url" {
  description = "Base URL of your Guild / Aiden tenant (no trailing slash)."
  type        = string
}

variable "stackgen_insecure" {
  description = "Allow plaintext HTTP to Guild (local development only)."
  type        = bool
  default     = false
}

variable "stackgen_token" {
  description = "Guild personal access token used by tofu to create runners, agents, and secrets."
  type        = string
  sensitive   = true
}

variable "stackgen_project_id" {
  description = "Optional Guild org / project ID when the tenant requires explicit scope."
  type        = string
  default     = ""
}

variable "model_names" {
  description = <<-EOT
    Names of models already registered in this Guild tenant (priority order).
    Copy from Guild UI → Models, or from another working agent. This is not an
    OpenAI / Anthropic / Gemini API key. This root does not install LLM providers.
  EOT
  type        = list(string)
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

variable "gitlab_token" {
  description = <<-EOT
    Optional GitLab PAT or deploy token. Prefer the GITLAB_TOKEN env var
    (maps to TF_VAR_gitlab_token). When set, this root creates a generic vault
    secret with flat env GITLAB_TOKEN / GIT_TOKEN (and GITLAB_BASE_URL when
    gitlab_base_url is set) and binds it on the runner.
    Leave empty until creds exist. Do not put the token in the runner image,
    tfvars, or task JSON. Omit the key entirely rather than setting "".
  EOT
  type        = string
  sensitive   = true
  default     = ""
}

variable "gitlab_base_url" {
  description = "Optional GitLab origin (e.g. https://gitlab.example.com). Prefer GITLAB_BASE_URL env. Synced as GITLAB_BASE_URL / GITLAB_HOST when gitlab_token is set."
  type        = string
  default     = ""
}

variable "existing_gitlab_secret_id" {
  description = "Optional pre-created generic sg_secret UUID with GITLAB_TOKEN (and optional GIT_TOKEN / GITLAB_BASE_URL). Mutually exclusive with gitlab_token."
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
