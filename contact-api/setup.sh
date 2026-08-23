#!/usr/bin/env bash
#
# Set up the OpsIntel contact-form handler on an always-on host:
#   install into /opt/opsintel-contact, create a virtualenv, write the .env, run
#   it as a systemd service on 127.0.0.1:8100, health-check it, and reload nginx.
#
# Credentials are taken from the environment or prompted for — they are NEVER
# baked into this script or committed. Run the static-site setup first
# (deploy/setup.sh), since that installs the nginx server block with the /api
# proxy this handler sits behind.
#
# Usage (either style):
#   sudo ./contact-api/setup.sh
#     -> prompts for the Brevo SMTP login + key
#   sudo SMTP_USER='<login>@smtp-brevo.com' SMTP_PASSWORD='<brevo-smtp-key>' ./contact-api/setup.sh
#
set -euo pipefail

APP_DIR="/opt/opsintel-contact"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- config (override any via env) ---
CONTACT_TO="${CONTACT_TO:-bikash.sen@opsintels.com}"
CONTACT_FROM="${CONTACT_FROM:-bikash.sen@opsintels.com}"
SMTP_HOST="${SMTP_HOST:-smtp-relay.brevo.com}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_STARTTLS="${SMTP_STARTTLS:-true}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run with sudo." >&2
  exit 1
fi

# --- credentials: from env, else prompt (kept out of the repo either way) ---
if [ -z "${SMTP_USER:-}" ]; then
  read -rp "Brevo SMTP login (e.g. xxxx@smtp-brevo.com): " SMTP_USER
fi
if [ -z "${SMTP_PASSWORD:-}" ]; then
  read -rsp "Brevo SMTP key: " SMTP_PASSWORD
  echo
fi
if [ -z "$SMTP_USER" ] || [ -z "$SMTP_PASSWORD" ]; then
  echo "SMTP_USER and SMTP_PASSWORD are required." >&2
  exit 1
fi

# --- a service account that exists on this distro ---
if id nginx >/dev/null 2>&1; then
  SVC_USER=nginx
elif id www-data >/dev/null 2>&1; then
  SVC_USER=www-data
else
  SVC_USER=root
fi

echo ">> Ensuring python3 + venv are installed…"
if command -v dnf >/dev/null 2>&1; then
  dnf install -y python3 python3-pip >/dev/null
elif command -v apt-get >/dev/null 2>&1; then
  apt-get update -y >/dev/null
  apt-get install -y python3 python3-venv python3-pip >/dev/null
fi

echo ">> Publishing the handler to $APP_DIR…"
mkdir -p "$APP_DIR"
cp "$SCRIPT_DIR/app.py" "$SCRIPT_DIR/requirements.txt" "$APP_DIR/"

echo ">> Creating the virtualenv and installing dependencies…"
python3 -m venv "$APP_DIR/.venv"
"$APP_DIR/.venv/bin/pip" install --quiet --upgrade pip
"$APP_DIR/.venv/bin/pip" install --quiet -r "$APP_DIR/requirements.txt"

echo ">> Writing $APP_DIR/.env (chmod 600)…"
umask 077
cat > "$APP_DIR/.env" <<ENV
CONTACT_TO=$CONTACT_TO
CONTACT_FROM=$CONTACT_FROM
SMTP_HOST=$SMTP_HOST
SMTP_PORT=$SMTP_PORT
SMTP_USER=$SMTP_USER
SMTP_PASSWORD=$SMTP_PASSWORD
SMTP_STARTTLS=$SMTP_STARTTLS
ENV
chmod 600 "$APP_DIR/.env"
chown -R "$SVC_USER:$SVC_USER" "$APP_DIR"

echo ">> Installing the systemd service (running as: $SVC_USER)…"
cat > /etc/systemd/system/opsintel-contact.service <<UNIT
[Unit]
Description=OpsIntel contact form handler
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/.venv/bin/gunicorn --workers 2 --bind 127.0.0.1:8100 app:app
Restart=always
RestartSec=3
User=$SVC_USER
Group=$SVC_USER

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable opsintel-contact >/dev/null 2>&1 || true
systemctl restart opsintel-contact

echo ">> Health check…"
sleep 1
if curl -fsS localhost:8100/api/contact/health >/dev/null 2>&1; then
  echo "   OK — handler is up on 127.0.0.1:8100"
else
  echo "   !! not responding yet — check: journalctl -u opsintel-contact -e" >&2
fi

echo ">> Reloading nginx…"
if command -v nginx >/dev/null 2>&1; then
  if ! grep -rq "location /api/" /etc/nginx/conf.d/ 2>/dev/null; then
    echo "   NOTE: no /api/ proxy found in nginx. Run deploy/setup.sh first so the" >&2
    echo "         site's server block (with the /api/ proxy) is installed." >&2
  fi
  if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx && echo "   nginx reloaded"
  else
    echo "   !! nginx -t failed; run 'sudo nginx -t' to see why." >&2
  fi
fi

echo ""
echo ">> Done. Verify end to end:"
echo "     curl -s -X POST https://opsintels.com/api/contact \\"
echo "          -H 'Content-Type: application/json' \\"
echo "          -d '{\"name\":\"Test\",\"email\":\"you@example.com\",\"message\":\"hi\"}'"
echo ""
echo "   IMPORTANT: CONTACT_FROM ($CONTACT_FROM) must be a VERIFIED sender in Brevo"
echo "   (Brevo -> Senders, Domains & Dedicated IPs), or sends will be rejected."
