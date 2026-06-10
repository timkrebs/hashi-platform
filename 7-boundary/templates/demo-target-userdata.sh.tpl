#!/usr/bin/env bash
set -euo pipefail

# Trust the Vault SSH CA: fetch its public key over the HVN peering
# (unauthenticated, read-only endpoint). Retry while routes/peering settle.
for attempt in $(seq 1 30); do
  if curl -fsS "${vault_addr}/v1/${ssh_mount_path}/public_key" \
    -o /etc/ssh/trusted-user-ca-keys.pem; then
    break
  fi
  echo "Vault CA fetch attempt $${attempt} failed; retrying in 10s" >&2
  sleep 10
done

test -s /etc/ssh/trusted-user-ca-keys.pem

cat > /etc/ssh/sshd_config.d/50-vault-ca.conf <<'EOF'
TrustedUserCAKeys /etc/ssh/trusted-user-ca-keys.pem
EOF

systemctl restart sshd
