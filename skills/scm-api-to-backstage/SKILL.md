---
name: scm-api-to-backstage
description: >
  Scan a GitLab (or other SCM) repository via REST APIs only — no clone —
  then emit Backstage catalog YAML shaped to a customer-provided template.
  Use when the user pastes a repo URL and wants inventory / catalog-info YAML
  for Backstage. Do not invent an upload or publish step unless the customer
  names a destination in the conversation.
---

# SCM API → Backstage catalog

Technical procedure for the attached remote runner. Follow this skill; do not
improvise alternate CLIs when `cce scm describe` is available.

## Inputs you need

1. **Repo identity** — GitLab URL or `group/sub/project` path (from the user).
2. **Catalog format** — customer Backstage entity shape. Sources, in order:
   - Template or example the user pasted / attached in this chat
   - Companion `references/catalog-template.example.yaml` on this skill (placeholder only)
   - If still missing: ask once for the target Backstage kind/fields. Do not invent a full custom schema.

## Tools

Use the attached remote runner shell tools (`*_execute_command`, `*_execute_series`).
If those tools are missing, say the runner is offline or not attached — do not invent YAML.

## Steps

### 1. Fetch forge metadata (API only)

Derive:

- `--repo` = path with namespace (e.g. `acme/checkout-api`)
- `--base-url` = GitLab origin when not gitlab.com (from runner `GITLAB_BASE_URL` / `GITLAB_HOST` when set; else omit)

Run (token already in runner env as `GITLAB_TOKEN` — never print it):

```text
cce scm describe --provider gitlab --repo <group/project> [--base-url <origin>] -o /tmp/cce-scm-meta.yaml
```

Confirm the file is non-empty (`test -s /tmp/cce-scm-meta.yaml`).

**Hard rule:** no `git clone`, no `glab repo clone`, no `cce --folder`, no `cce --repo` for this skill.

### 2. Map metadata → customer Backstage YAML

Read `/tmp/cce-scm-meta.yaml`. Typical fields to map into the customer template:

| scmmeta path | Common Backstage use |
|---|---|
| `repository.full_name` / `repository.name` | `metadata.name` (normalize to kebab-case if template requires) |
| `repository.description` | `metadata.description` |
| `repository.html_url` / `clone_url` | `metadata.annotations` source-location / repo URL |
| `repository.default_branch` | annotation or `spec` field if template has it |
| `provider` / `host` / `repo` | SCM annotations |
| `extensions.gitlab.*` | only if the customer template asks for GitLab-specific keys |

Emit the catalog document(s) the customer format requires (often one `Component`, sometimes extra `API` / `Resource` docs). Write to `/tmp/cce-catalog.yaml` on the runner when useful, then return the YAML in chat inside a fenced `yaml` block.

Preserve customer field names and required keys. Do not “fix” with StackGen-only annotations unless the template includes them.

### 3. After the scan (stop here by default)

Deliver:

1. The Backstage YAML (verbatim from the file or generated document)
2. A short note of source repo + that metadata came from SCM API (`cce scm describe`)

**Do not** push, open a PR, call a registry API, write to S3/Git, or otherwise publish the YAML unless the customer **explicitly** names where to put it in this conversation. If they have not said, ask once: “Where should this catalog YAML go?” and wait.

## Failure handling

- Describe fails → report API egress, missing `GITLAB_TOKEN` sync, wrong `--base-url`, or Helm `ALLOWED_CLIS` omitting `cce`. Do not invent catalog YAML.
- Template incomplete → ask for the missing fields; do not guess org-specific `spec.type` / ownership conventions.
