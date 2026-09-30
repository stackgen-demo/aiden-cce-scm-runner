package policy

import rego.v1

# Read-only guard for the CCE SCM analyst: deny mutating shell on the runner.
# Describe (API) and gated clone+scan remain allowed.

default allow := true

cmd := lower(object.get(input.tool.arguments, "command", ""))

allow := false if {
	endswith(input.tool.name, "_execute_command")
	write_action(cmd)
}

allow := false if {
	endswith(input.tool.name, "_execute_series")
	write_action(cmd)
}

allow := false if {
	endswith(input.tool.name, ":execute_command")
	write_action(cmd)
}

# Remote / forge mutations
write_action(cmd) if contains(cmd, "git push")
write_action(cmd) if contains(cmd, "git commit")
write_action(cmd) if contains(cmd, "git tag")
write_action(cmd) if contains(cmd, "glab mr create")
write_action(cmd) if contains(cmd, "glab mr merge")
write_action(cmd) if contains(cmd, "glab issue create")
write_action(cmd) if contains(cmd, "glab release create")
write_action(cmd) if contains(cmd, "glab repo create")
write_action(cmd) if contains(cmd, "glab api --method post")
write_action(cmd) if contains(cmd, "glab api --method put")
write_action(cmd) if contains(cmd, "glab api --method patch")
write_action(cmd) if contains(cmd, "glab api --method delete")
write_action(cmd) if contains(cmd, "gh pr create")
write_action(cmd) if contains(cmd, "gh pr merge")
write_action(cmd) if contains(cmd, "gh release create")

# HTTP write verbs (e.g. curl against GitLab)
write_action(cmd) if {
	contains(cmd, "curl")
	contains(cmd, " -x post")
}

write_action(cmd) if {
	contains(cmd, "curl")
	contains(cmd, " -x put")
}

write_action(cmd) if {
	contains(cmd, "curl")
	contains(cmd, " -x patch")
}

write_action(cmd) if {
	contains(cmd, "curl")
	contains(cmd, " -x delete")
}

write_action(cmd) if {
	contains(cmd, "curl")
	contains(cmd, "--request post")
}

write_action(cmd) if {
	contains(cmd, "curl")
	contains(cmd, "--request put")
}

write_action(cmd) if {
	contains(cmd, "curl")
	contains(cmd, "--request patch")
}

write_action(cmd) if {
	contains(cmd, "curl")
	contains(cmd, "--request delete")
}

# Destructive / infra writes
write_action(cmd) if contains(cmd, "rm -rf")
write_action(cmd) if contains(cmd, "terraform apply")
write_action(cmd) if contains(cmd, "terraform destroy")
write_action(cmd) if contains(cmd, "tofu apply")
write_action(cmd) if contains(cmd, "tofu destroy")
write_action(cmd) if contains(cmd, "kubectl apply")
write_action(cmd) if contains(cmd, "kubectl delete")
write_action(cmd) if contains(cmd, "kubectl patch")
write_action(cmd) if contains(cmd, "helm install")
write_action(cmd) if contains(cmd, "helm upgrade")
write_action(cmd) if contains(cmd, "helm uninstall")
write_action(cmd) if contains(cmd, "helm delete")

deny_reason := "This agent is read-only: write actions are not allowed." if {
	not allow
}
