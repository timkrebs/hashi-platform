# vault-aws-prerequisites

The AWS side of a Vault installation whose pods are deployed by Argo CD:

- a **KMS key** for auto-unseal with a deterministic alias
  (`alias/<name_prefix>-vault-unseal`), so Vault's `awskms` seal can reference
  it by name and a rebuilt environment finds it under the same alias;
- an **IRSA role** for the Vault server service account, limited to
  `kms:Encrypt`, `kms:Decrypt` and `kms:DescribeKey` on that key;
- a **Secrets Manager secret** that receives the output of
  `vault operator init` (recovery keys, root token, CA certificate) and an
  **IRSA role** for the init job that may only write that one secret.

Vault itself, its TLS material and the init job live under `gitops/`; this
module only provides what they need from AWS and exports the identifiers the
Argo CD cluster secret hands to them.

## Usage

```hcl
module "vault_prerequisites" {
  source = "../../../modules/vault-aws-prerequisites"

  name_prefix      = "hashi-platform-dev"
  oidc_provider    = data.terraform_remote_state.cluster.outputs.oidc_provider
  init_secret_name = "hashi-platform/dev/vault/init"

  # ephemeral environment
  kms_key_deletion_window_in_days = 7
  secret_recovery_window_in_days  = 0

  tags = local.common_tags
}
```

## Requirements

| Name      | Version            |
|-----------|--------------------|
| terraform | >= 1.9.0           |
| aws       | >= 5.47.0, < 6.0.0 |

## Inputs

| Name                            | Description                                                                 | Type          | Default                       | Required |
|---------------------------------|-----------------------------------------------------------------------------|---------------|-------------------------------|:--------:|
| name_prefix                     | Prefix for all names, typically `<project>-<environment>` (1-50 chars)      | `string`      | n/a                           | yes      |
| oidc_provider                   | Cluster OIDC issuer URL without `https://`                                  | `string`      | n/a                           | yes      |
| namespace                       | Namespace Vault runs in                                                     | `string`      | `"vault"`                     | no       |
| service_account                 | Vault server service account                                                | `string`      | `"vault"`                     | no       |
| init_service_account            | Init job service account                                                    | `string`      | `"vault-init"`                | no       |
| init_secret_name                | Secrets Manager secret name for the init output                             | `string`      | `<name_prefix>/vault/init`    | no       |
| kms_key_deletion_window_in_days | KMS deletion window after destroy (7-30)                                    | `number`      | `30`                          | no       |
| secret_recovery_window_in_days  | Secret recovery window after destroy (0 or 7-30)                            | `number`      | `30`                          | no       |
| tags                            | Tags for every resource                                                     | `map(string)` | `{}`                          | no       |

## Outputs

| Name                     | Description                                              |
|--------------------------|----------------------------------------------------------|
| kms_key_arn              | ARN of the unseal key                                    |
| kms_key_id               | ID of the unseal key                                     |
| kms_key_alias            | Alias of the unseal key, for the `awskms` seal           |
| vault_irsa_role_arn      | Role the Vault server assumes                            |
| vault_init_irsa_role_arn | Role the init job assumes                                |
| init_secret_arn          | ARN of the init secret                                   |
| init_secret_name         | Name of the init secret                                  |

## Tests

```sh
terraform init -backend=false
terraform test
```

Plan-mode unit tests with a mocked `aws` provider; policy documents are
overridden with valid JSON and the IRSA modules with fixed outputs.
