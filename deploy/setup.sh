#!/usr/bin/env bash
#
# Publish the OpsIntels landing page behind nginx + Let's Encrypt on an
# always-on host (e.g. a free-tier EC2 instance).
#
# Prerequisites:
#   1. opsintels.com (and www.opsintels.com) A records -> this instance's IP.
#   2. Security group inbound: TCP 80 and 443 open to 0.0.0.0/0.
#
# Usage:
#   sudo LE_EMAIL=you@example.com ./deploy/setup.sh
#   (LE_EMAIL is optional but recommended — it gets expiry warnings.)
set -euo pipefail

DOMAIN="opsintels.com"
WWW="www.opsintels.com"
WEBROOT="/var/www/opsintels"
LE_EMAIL="${LE_EMAIL:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITE_DIR="$(dirname "$SCRIPT_DIR")"

echo ">> Installing nginx + certbot…"
if command -v dnf >/dev/null 2>&1; then
  sudo dnf install -y nginx certbot python3-certbot-nginx
else
  sudo apt-get update -y
  sudo apt-get install -y nginx certbot python3-certbot-nginx
  sudo rm -f /etc/nginx/sites-enabled/default
fi
sudo systemctl enable --now nginx

echo ">> Publishing the site to $WEBROOT…"
sudo mkdir -p "$WEBROOT"
sudo cp "$SITE_DIR/index.html" "$SITE_DIR/favicon.svg" "$WEBROOT/"

echo ">> Writing the nginx server block…"
sudo cp "$SCRIPT_DIR/nginx-opsintels.conf" /etc/nginx/conf.d/opsintels.conf
sudo nginx -t
sudo systemctl reload nginx

echo ">> Obtaining a Let's Encrypt certificate for $DOMAIN + $WWW…"
email_arg=(--register-unsafely-without-email)
if [ -n "$LE_EMAIL" ]; then
  email_arg=(-m "$LE_EMAIL")
fi
sudo certbot --nginx -d "$DOMAIN" -d "$WWW" --non-interactive --agree-tos --redirect "${email_arg[@]}"

echo ""
echo ">> Done. https://$DOMAIN is live."
echo ">> To update later: git pull && sudo cp index.html favicon.svg $WEBROOT/"
