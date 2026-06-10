# Least-privilege policies per consumer. Boundary's credential store holds a
# periodic orphan token (minted in Layer 7) carrying exactly these two.

# What Boundary needs to keep its own credential-store token alive.
resource "vault_policy" "boundary_controller" {
  name = "boundary-controller"

  policy = <<-EOT
    path "auth/token/lookup-self" {
      capabilities = ["read"]
    }

    path "auth/token/renew-self" {
      capabilities = ["update"]
    }

    path "auth/token/revoke-self" {
      capabilities = ["update"]
    }

    path "sys/leases/renew" {
      capabilities = ["update"]
    }

    path "sys/leases/revoke" {
      capabilities = ["update"]
    }

    path "sys/capabilities-self" {
      capabilities = ["update"]
    }
  EOT
}

# What Boundary's SSH certificate credential library is allowed to do:
# sign client keys with the boundary-client role, nothing else.
resource "vault_policy" "ssh_signer" {
  name = "ssh-signer"

  policy = <<-EOT
    path "${vault_mount.ssh.path}/sign/${vault_ssh_secret_backend_role.boundary_client.name}" {
      capabilities = ["create", "update"]
    }
  EOT
}
