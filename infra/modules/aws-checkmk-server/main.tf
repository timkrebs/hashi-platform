# Checkmk Raw Edition on a single Ubuntu 24.04 instance. The package is
# downloaded and verified at first boot; the admin password is generated here,
# stored as an SSM SecureString, and read by the instance through its instance
# profile, so it never travels in user data.
#
# Shell access is through SSM Session Manager: there is no key pair and no
# port 22.

data "aws_partition" "current" {}

# The company's hardened Ubuntu 24.04 base image. 24.04 is required rather than
# preferred: Checkmk publishes no build for 26.04, and the hardened family is
# built on noble, so the pinned .deb still matches.
data "aws_ami" "hardened" {
  count = var.ami_id == null ? 1 : 0

  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = ["${var.ami_name_prefix}-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  tags = merge(var.tags, { Name = var.name })

  ami_id = var.ami_id != null ? var.ami_id : one(data.aws_ami.hardened[*].id)

  # One rule per port and CIDR, so each can be asserted by key in the tests.
  ingress_rules = merge([
    for port in [80, 443] : {
      for cidr in var.allowed_cidr_blocks :
      "${port}-${cidr}" => { port = port, cidr = cidr }
    }
  ]...)

  user_data = <<USERDATA
#!/usr/bin/env bash
# Rendered by Terraform (infra/modules/aws-checkmk-server). Do not edit on the
# host: the instance is replaced whenever this script changes.
set -euo pipefail

SITE="${var.site_name}"
REGION="${var.region}"
PARAM="${aws_ssm_parameter.admin_password.name}"
DEB_URL="${var.package_url}"
DEB_SHA256="${var.package_sha256}"
DEB_PATH=/var/tmp/checkmk.deb

export DEBIAN_FRONTEND=noninteractive
# The lock timeout matters: unattended-upgrades holds the dpkg lock for the
# first minute of a fresh boot, and set -e would abort the bootstrap.
APT="apt-get -o DPkg::Lock::Timeout=600 -o Dpkg::Use-Pty=0 -y"

log() { echo "[checkmk] $*"; }

log "bootstrap started $(date -Is)"

# 1. Prerequisites. Ubuntu 24.04 ships no awscli package, so boto3 reads SSM.
$APT update
$APT install --no-install-recommends ca-certificates curl python3-boto3 ssl-cert

# 2. Download and verify against the pinned checksum. The elastic IP is
# associated moments after launch and drops connections made over the
# auto-assigned address, so resume and retry generously.
curl --fail --location --silent --show-error \
     --retry 10 --retry-delay 15 --retry-connrefused --continue-at - \
     --output "$DEB_PATH" "$DEB_URL"
echo "$DEB_SHA256  $DEB_PATH" | sha256sum --check --strict -

# 3. Install. apt resolves the dependencies that dpkg -i would leave broken.
$APT install "$DEB_PATH"

# 4. Read the admin password, retrying because IAM is eventually consistent.
read_password() {
  python3 - "$REGION" "$PARAM" <<'PY'
import sys, boto3
region, name = sys.argv[1], sys.argv[2]
sys.stdout.write(
    boto3.client("ssm", region_name=region)
    .get_parameter(Name=name, WithDecryption=True)["Parameter"]["Value"]
)
PY
}

CMK_PASSWORD=""
for attempt in $(seq 1 30); do
  if CMK_PASSWORD="$(read_password 2>/dev/null)" && [ -n "$CMK_PASSWORD" ]; then
    break
  fi
  log "SSM GetParameter attempt $attempt failed; retrying in 10s"
  sleep 10
done
if [ -z "$CMK_PASSWORD" ]; then
  log "could not read $PARAM from SSM; aborting"
  exit 1
fi

# 5. Create the site. Output goes to a file because omd echoes the password and
# cloud-init copies script output to the serial console, which is readable
# through ec2 get-console-output.
if [ ! -d "/omd/sites/$SITE" ]; then
  umask 077
  if omd create --admin-password "$CMK_PASSWORD" "$SITE" >/root/omd-create.log 2>&1; then
    rm -f /root/omd-create.log
    log "site $SITE created"
  else
    grep -vi password /root/omd-create.log >/root/omd-create-redacted.log || true
    rm -f /root/omd-create.log
    log "omd create failed; see /root/omd-create-redacted.log"
    exit 1
  fi
  umask 022
else
  log "site $SITE already exists"
fi
unset CMK_PASSWORD

# 6. Autostart. omd config only works on a stopped site, so it has to run
# between create and start.
omd config "$SITE" set AUTOSTART on

# 7. TLS on the system Apache, which reverse-proxies /$SITE/ to the site.
a2enmod ssl headers rewrite
make-ssl-cert generate-default-snakeoil --force-overwrite

cat > /etc/apache2/sites-available/checkmk-ssl.conf <<'SSLCONF'
<IfModule mod_ssl.c>
<VirtualHost *:443>
    SSLEngine on
    SSLCertificateFile    /etc/ssl/certs/ssl-cert-snakeoil.pem
    SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key

    # Without these the site believes the request arrived over plain HTTP,
    # builds http:// URLs, and every login bounces back to the login page.
    <IfModule mod_headers.c>
        RequestHeader set X-Forwarded-Proto expr=%%{REQUEST_SCHEME}
        RequestHeader set X-Forwarded-SSL   expr=%%{HTTPS}
    </IfModule>

    ErrorLog  $${APACHE_LOG_DIR}/checkmk-ssl-error.log
    CustomLog $${APACHE_LOG_DIR}/checkmk-ssl-access.log combined
</VirtualHost>
</IfModule>
SSLCONF

cat > /etc/apache2/sites-available/checkmk-redirect.conf <<'REDIRCONF'
<VirtualHost *:80>
    RewriteEngine On
    RewriteRule ^/?(.*) https://%%{HTTP_HOST}/$1 [R=301,L]
</VirtualHost>
REDIRCONF

cat > /etc/apache2/conf-available/zzz-checkmk-root.conf <<ROOTCONF
RedirectMatch ^/\$ /$SITE/
ROOTCONF

a2ensite checkmk-ssl checkmk-redirect
a2enconf zzz-checkmk-root
a2dissite 000-default || true

# 8. The site first, then the proxy in front of it, so there is no 503 window.
omd start "$SITE"
systemctl enable apache2
apache2ctl configtest
systemctl restart apache2

# 9. Hardened images often ship a host firewall that is closed by default, so
# the security group alone would not be enough to reach the interface.
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi '^Status: active'; then
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  log "opened 80 and 443 in ufw"
fi

# 10. Session Manager. The agent is preinstalled on the hardened images; this
# only covers a custom ami_id that lacks it, and never fails the bootstrap.
if ! systemctl is-active --quiet snap.amazon-ssm-agent.amazon-ssm-agent 2>/dev/null &&
   ! systemctl is-active --quiet amazon-ssm-agent 2>/dev/null; then
  if command -v snap >/dev/null 2>&1; then
    snap install amazon-ssm-agent --classic || log "could not install the SSM agent"
    snap start --enable amazon-ssm-agent || true
  else
    log "no SSM agent and no snapd; Session Manager will be unavailable"
  fi
fi

touch /var/lib/checkmk-bootstrap.done
log "bootstrap finished $(date -Is)"
USERDATA
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

resource "aws_security_group" "this" {
  name        = var.name
  description = "Checkmk web interface and outbound access for ${var.name}"
  vpc_id      = var.vpc_id

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = local.ingress_rules

  security_group_id = aws_security_group.this.id
  description       = "Checkmk web interface on ${each.value.port} from ${each.value.cidr}"
  cidr_ipv4         = each.value.cidr
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port

  tags = local.tags
}

# Outbound is needed for apt, the package download and the SSM endpoints.
resource "aws_vpc_security_group_egress_rule" "this" {
  security_group_id = aws_security_group.this.id
  description       = "All outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Instance identity
# ---------------------------------------------------------------------------

resource "aws_iam_role" "this" {
  name        = "${var.name}-instance"
  description = "Role assumed by the ${var.name} Checkmk server."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = local.tags
}

# What makes Session Manager work, and why no key pair is needed.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Read access to exactly one parameter. kms:Decrypt is scoped with a condition
# rather than to the alias/aws/ssm key, because that AWS-managed key is created
# lazily on the first SecureString write and would not resolve in a fresh account.
resource "aws_iam_role_policy" "admin_password" {
  name = "${var.name}-admin-password"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadAdminPassword"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = aws_ssm_parameter.admin_password.arn
      },
      {
        Sid       = "DecryptAdminPassword"
        Effect    = "Allow"
        Action    = ["kms:Decrypt"]
        Resource  = "*"
        Condition = { StringEquals = { "kms:ViaService" = "ssm.${var.region}.amazonaws.com" } }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "this" {
  name = var.name
  role = aws_iam_role.this.name

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Initial credential
# ---------------------------------------------------------------------------

# The character set deliberately excludes quotes, backslash and $ so the value
# can never break shell quoting in the bootstrap.
resource "random_password" "admin" {
  length           = var.admin_password_length
  special          = true
  override_special = "!#%*+,-.:=?@^_~"
}

resource "aws_ssm_parameter" "admin_password" {
  name        = "/${var.name}/cmkadmin-password"
  description = "Initial cmkadmin password for the ${var.name} Checkmk site. Authoritative only until it is changed in the interface."
  type        = "SecureString"
  value       = random_password.admin.result

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

resource "aws_instance" "this" {
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = true
  monitoring                  = false

  # base64 rather than user_data, which the provider stores as a hash and which
  # the unit tests therefore could not inspect.
  user_data_base64            = base64encode(local.user_data)
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true

    tags = local.tags
  }

  tags = local.tags

  # Neither grant has an implicit edge to the instance, so without this the
  # instance can boot before they exist and the first GetParameter is denied.
  depends_on = [
    aws_iam_role_policy.admin_password,
    aws_iam_role_policy_attachment.ssm_core,
  ]
}

# A stable address: the auto-assigned public IP does not survive a stop/start.
resource "aws_eip" "this" {
  instance = aws_instance.this.id
  domain   = "vpc"

  tags = local.tags
}
