# Layer 1b — HCP Terraform agent

A single self-healing agent instance (ASG of 1) in a private subnet, registered
to the `hashi-platform-vpc` agent pool created by `0-bootstrap`.

**Why it exists:** HCP Terraform's hosted runners live on the public internet and
cannot reach the platform's private endpoints (Vault on the HVN now; Consul and
Nomad APIs later). Workspaces `3-vault-config` through `8-cicd-observe` run in
**agent mode** on this instance instead — the standard enterprise pattern for
private-endpoint configuration.

- Token flow: `0-bootstrap` (local) writes the agent token to SSM Parameter Store
  (SecureString); the instance reads it at boot via its instance profile. The token
  never appears in VCS-driven workspace state.
- Outbound-only security group; no inbound rules. Break-glass access is SSM
  Session Manager until Boundary covers it.
- `TFC_AGENT_AUTO_UPDATE=minor` keeps the agent current after the pinned install.

## Run

Depends on: `0-bootstrap` re-applied (agent pool + SSM parameter exist) and
Layer 1 applied. PR → merge → confirm apply in workspace `1-tfc-agent`.

## Definition of Done

HCP Terraform → org **Settings → Agents → hashi-platform-vpc** shows the agent
**Idle/Ready** within ~3 minutes of the ASG launching the instance.

## Note on plans

Agent pools require a plan that includes self-hosted agents (the Free tier
includes one agent — exactly this topology). If `0-bootstrap` errors creating
the pool, check your organization's plan page.
