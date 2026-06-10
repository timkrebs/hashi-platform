#!/usr/bin/env bash
set -euo pipefail

dnf install -y unzip

TOKEN=$(aws ssm get-parameter \
  --name "${ssm_parameter_name}" \
  --with-decryption \
  --region "${region}" \
  --query 'Parameter.Value' \
  --output text)

useradd --system --create-home tfc-agent || true

curl -fsSLo /tmp/tfc-agent.zip \
  "https://releases.hashicorp.com/tfc-agent/${version}/tfc-agent_${version}_linux_amd64.zip"
unzip -o /tmp/tfc-agent.zip -d /opt/tfc-agent
rm -f /tmp/tfc-agent.zip

cat > /etc/tfc-agent.env <<EOF
TFC_AGENT_TOKEN=$${TOKEN}
TFC_AGENT_NAME=$(hostname)
TFC_AGENT_AUTO_UPDATE=minor
EOF
chmod 600 /etc/tfc-agent.env

cat > /etc/systemd/system/tfc-agent.service <<'EOF'
[Unit]
Description=HCP Terraform agent
After=network-online.target
Wants=network-online.target

[Service]
User=tfc-agent
EnvironmentFile=/etc/tfc-agent.env
ExecStart=/opt/tfc-agent/tfc-agent
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now tfc-agent
