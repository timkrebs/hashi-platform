#!/usr/bin/env bash
set -euo pipefail

dnf install -y yum-utils
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
dnf install -y boundary-worker

mkdir -p /etc/boundary.d /var/lib/boundary-worker

cat > /etc/boundary.d/worker.hcl <<EOF
disable_mlock = true

hcp_boundary_cluster {
  cluster_id = "${boundary_cluster_uuid}"
}

worker {
  auth_storage_path                     = "/var/lib/boundary-worker"
  controller_generated_activation_token = "${activation_token}"

  tags {
    type = ["egress", "vault"]
  }
}
EOF

chown -R boundary:boundary /var/lib/boundary-worker
chmod 600 /etc/boundary.d/worker.hcl

systemctl enable --now boundary-worker
