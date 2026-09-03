# Sentinel policies

Policy-as-code guardrails evaluated by HCP Terraform after every plan in the
`hashi-platform` project. A run that violates a `hard-mandatory` policy cannot
be applied.

| Policy                    | What it enforces                                                                                       | Level          |
|---------------------------|--------------------------------------------------------------------------------------------------------|----------------|
| `require-mandatory-tags`  | Every AWS resource that supports tags carries `Environment`, `Project` and `ManagedBy`                 | hard-mandatory |
| `restrict-compute-size`   | No instance type larger than `medium` (nano, micro, small, medium allowed) anywhere compute is defined | hard-mandatory |

Both policies look at `tfplan/v2` resource changes with `create` or `update`
actions. Deletes, data sources and non-AWS providers are ignored.

## require-mandatory-tags

- A resource counts as taggable when its planned attributes include `tags`.
  Resources without a `tags` attribute (route table associations, security
  group rules, IAM policy attachments, KMS aliases, and so on) cannot be tagged
  and are skipped.
- Tags may come from the resource's own `tags` or from the provider's
  `default_tags`, which Terraform exposes as `tags_all`. Either satisfies the
  policy.
- A mandatory tag whose *value* is only known after apply still passes, since
  the key is set. A resource whose *entire* tag map is unknown fails, because
  the plan cannot prove it will be tagged.
- The tag list is a policy parameter (`mandatory_tags`).

## restrict-compute-size

- Checks `instance_types` on `aws_eks_node_group`; `instance_type` on
  `aws_instance`, `aws_launch_template`, `aws_launch_configuration` and
  `aws_spot_instance_request`; and every `mixed_instances_policy` override on
  `aws_autoscaling_group`.
- The size is the part after the dot, so `t3.medium` passes while `m5.large`,
  `c6i.metal` and `m7i-flex.large` fail.
- An instance type unknown until apply fails closed.
- The allowed sizes are a policy parameter (`allowed_sizes`).

## How the set is attached

In HCP Terraform the policy set `hp-dev-compliance` is a Sentinel set scoped
to the `hashi-platform` project, sourced from this repository with policies
path `infra/policies`. HCP Terraform reads `sentinel.hcl` from that path on
the configured branch, so a change to a policy takes effect once it lands on
that branch.

## Testing locally

Download the Sentinel CLI from
[releases.hashicorp.com/sentinel](https://releases.hashicorp.com/sentinel/)
(or `brew install hashicorp/tap/sentinel`), then:

```sh
cd infra/policies
sentinel fmt -check *.sentinel testdata/*.sentinel
sentinel test -verbose
```

or `make policy-test` from the repository root. Tests live in
`test/<policy-name>/` and use the mocks in `testdata/`, which are small,
sanitised `tfplan/v2` documents modelled on the dev environment plan.

To evaluate a policy against a real plan, open a run in HCP Terraform, choose
*Download Sentinel mocks*, unpack the bundle and run:

```sh
sentinel apply -trace -config=<bundle>/sentinel.hcl require-mandatory-tags.sentinel
```

Do not commit real mock bundles: they contain account IDs and identity ARNs.

## Changing enforcement

Edit the `enforcement_level` in `sentinel.hcl`. `soft-mandatory` lets users
with the *manage policy overrides* permission approve a run that violates the
policy, which is useful while rolling a new rule out.
