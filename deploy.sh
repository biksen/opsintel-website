#!/usr/bin/env bash
#
# One-command deploy for opsintels.com.
#
# Publishes the static site (nginx + HTTPS on the first run) and sets up /
# refreshes the contact-form handler. Idempotent — safe to re-run after every
# `git pull`: later runs just republish the site and update the handler.
#
# Credentials come from the environment or an interactive prompt — never
# committed. Prerequisites for the FIRST run: opsintels.com (+ www) DNS points at
# this host, and the security group allows TCP 80 + 443.
#
# Usage:
#   sudo ./deploy.sh
#   sudo LE_EMAIL=you@opsintels.com \
#        SMTP_USER=you@opsintels.com SMTP_PASSWORD='...' ./deploy.sh
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DOMAIN="opsintels.com"
WWW="www.opsintels.com"
WEBROOT="/var/www/opsintels"
NGINX_CONF="/etc/nginx/conf.d/opsintels.conf"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run with sudo." >&2
  exit 1
fi

echo "==> Installing nginx / certbot / python if needed…"
if command -v dnf >/dev/null 2>&1; then
  dnf install -y nginx certbot python3-certbot-nginx python3 python3-pip >/dev/null
elif command -v apt-get >/dev/null 2>&1; then
  apt-get update -y >/dev/null
  apt-get install -y nginx certbot python3-certbot-nginx python3 python3-venv python3-pip >/dev/null
  rm -f /etc/nginx/sites-enabled/default
fi
systemctl enable --now nginx >/dev/null 2>&1 || true

echo "==> Publishing the site to $WEBROOT…"
mkdir -p "$WEBROOT"
cp "$SCRIPT_DIR/index.html" "$SCRIPT_DIR/favicon.svg" "$WEBROOT/"

# Install the server block + certificate only the first time (detected by the
# /api proxy already being present); afterwards just reload, so we never clobber
# certbot's HTTPS block.
if ! grep -q "location /api/" "$NGINX_CONF" 2>/dev/null; then
  echo "==> First-time nginx server block + Let's Encrypt certificate…"
  cp "$SCRIPT_DIR/deploy/nginx-opsintels.conf" "$NGINX_CONF"
  nginx -t && systemctl reload nginx
  email_arg=(--register-unsafely-without-email)
  [ -n "${LE_EMAIL:-}" ] && email_arg=(-m "$LE_EMAIL")
  certbot --nginx -d "$DOMAIN" -d "$WWW" --non-interactive --agree-tos --redirect \
    --keep-until-expiring "${email_arg[@]}"
else
  echo "==> nginx already configured (site + /api proxy present) — reloading."
  nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
fi

echo "==> Setting up / refreshing the contact handler…"
bash "$SCRIPT_DIR/contact-api/setup.sh"

echo ""
echo "==> Deploy complete."
echo "    Test end to end:"
echo "      curl -s -X POST https://$DOMAIN/api/contact \\"
echo "           -H 'Content-Type: application/json' \\"
echo "           -d '{\"name\":\"Test\",\"email\":\"visitor@example.com\",\"message\":\"hi\"}'"
echo "    Then check bikash.sen@opsintels.com (incl. spam)."
