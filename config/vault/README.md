# Vault configuration

Configures a Vault Enterprise cluster that already exists. Nothing here creates
Vault itself — that is the `vault` Argo CD Application in `gitops/`.

The layout follows the namespace model: the root namespace holds the
certificate authorities and the administrator, and each team namespace owns its
own auth method, policies and secrets engines. A tenant can therefore be handed
over, or removed, without touching the others.

```text
root namespace
├── auth/userpass         timkrebs, policy "admin"
├── root-pki              root CA, private key never leaves Vault
└── intermediate-pki      signed by root-pki
hp-dev-backend
├── auth/userpass         dev1, policy "dev"
├── kv (kv-v2)            api-key
└── pki-dev               signed by root-pki, role "dev"
hp-dev-frontend
├── auth/userpass         dev2, policy "dev"
└── kv (kv-v2)            api-key
```

## Isolation

`dev1` and `dev2` live inside their namespace, not in the root namespace. The
separation is therefore structural rather than a matter of writing the policies
correctly: `dev1` simply does not exist in `hp-dev-frontend`, so no policy
mistake can grant access across the boundary. The cost is that a login has to
name its namespace.

## Passwords

All three passwords are inputs, never generated here. Set `admin_password`,
`dev1_password` and `dev2_password` as **sensitive** variables in the HCP
Terraform workspace.

The two demo API keys are the exception: they are generated with
`random_password`, because their point is to be read out of Vault. They are
deliberately not outputs.

## First apply

The workspace needs `vault_address` and a `vault_token`. The initial root token
works for the first apply. Afterwards, log in as the administrator and revoke
the root token — that is the whole reason the `admin` policy exists rather than
using root forever:

```sh
terraform output -raw admin_login_command   # vault login -method=userpass ...
vault token revoke -self                    # with the root token still set
```

### Reaching Vault over TLS

Two separate things have to line up, and they fail with different errors.

**The CA.** Vault's certificate comes from the in-cluster cert-manager CA, which
no public trust store knows. Point `vault_ca_cert_file` at that CA or set
`VAULT_CACERT` on the runner, otherwise the error is
`x509: certificate signed by unknown authority`.

**The name.** cert-manager issued the certificate for the in-cluster names, and
`vault_address` points at the load balancer, whose AWS-generated hostname is not
among them. The error then names both sides:

```
certificate is valid for vault, vault.vault, vault.vault.svc,
vault.vault.svc.cluster.local, *.vault-internal, ...
not k8s-vault-vaultui-....elb.us-east-1.amazonaws.com
```

`vault_tls_server_name` defaults to `vault.vault.svc.cluster.local` for exactly
this reason. It is a default rather than something you have to set, because a
null default here fails silently: the configuration looks correct and the
connection fails as if the setting were not there at all. The connection
still goes to the load balancer and the chain is still verified against the CA —
only the name check is redirected to a name the certificate carries. A man in
the middle would still need a certificate from that same private CA.

Adding the load balancer hostname to the `Certificate` in
`gitops/manifests/vault-pki` would be the more literal fix, and is worth doing
once the address is stable. It is AWS-generated and changes whenever the load
balancer is recreated, so it would have to be updated by hand each time.

`vault_skip_tls_verify` exists as a last resort. Prefer not to use it here: this
connection carries the Vault token across the public internet, and skipping
verification is exactly what lets someone else collect it.

## Certificate authorities

`root-pki` signs two intermediates: `intermediate-pki` in the root namespace for
platform workloads, and `pki-dev` inside `hp-dev-backend` so the backend team
can issue its own development certificates. The signing is cross-namespace: the
request is created in the tenant namespace, signed in the root namespace, and
the result handed back, so the tenant never sees the root CA private key.

Chaining `pki-dev` off `intermediate-pki` instead of off the root would be the
more conventional shape, and would let the root be taken offline. It is signed
by the root here because that is what the environment was specified to do.

```sh
terraform output -raw backend_issue_command
terraform output -raw root_ca_certificate > root-ca.pem
```

## Checks

```sh
make check          # covers this root through CONFIG_DIRS
```

`terraform validate` needs `terraform init -backend=false`, because the `cloud`
block points at the `hashi-platform-vault` workspace, which has to exist before
a real plan can run.
