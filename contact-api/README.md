# contact-api

A tiny server-side handler for the site's contact form, so a submission is
**emailed silently** (no mail-app popup) and the recipient address never appears
in the browser. Flask + SMTP, run behind nginx on `127.0.0.1:8100`.

```
POST /api/contact   {name, email, phone, message}   ->   {"ok": true}
```

## Quick setup (one script)

From the repo on the EC2, after `deploy/setup.sh` has installed nginx:

```bash
sudo ./contact-api/setup.sh
```

It prompts for your Brevo SMTP login + key (or pass them as `SMTP_USER` /
`SMTP_PASSWORD` env vars), then installs to `/opt/opsintel-contact`, creates the
virtualenv, writes `.env` (chmod 600), starts the systemd service, health-checks
it, and reloads nginx. Credentials are never written to the repo. Re-run it any
time to update. The manual steps below are the same thing, spelled out.

## Manual setup

**1. Install it** (paths here match the systemd unit; adjust if you differ):

```bash
sudo mkdir -p /opt/opsintel-contact
sudo cp -r contact-api/* /opt/opsintel-contact/
cd /opt/opsintel-contact
sudo python3 -m venv .venv
sudo .venv/bin/pip install -r requirements.txt
```

**2. Configure delivery** — copy the example and fill in your SMTP details:

```bash
sudo cp .env.example .env
sudo nano .env          # set CONTACT_TO, SMTP_HOST, SMTP_USER, SMTP_PASSWORD…
sudo chmod 600 .env
```

**Brevo** (free tier) works well: `smtp-relay.brevo.com:587`, TLS, using your
Brevo SMTP login + key. The `CONTACT_FROM` address must be a **verified sender**
in Brevo (Senders & IP → add/verify the sender, or authenticate the `opsintels.com`
domain for best deliverability). Amazon SES or any other SMTP provider works too.

**3. Run it as a service:**

```bash
sudo cp opsintel-contact.service /etc/systemd/system/
# edit User=/Group= if your distro uses www-data instead of nginx
sudo systemctl daemon-reload
sudo systemctl enable --now opsintel-contact
curl -s localhost:8100/api/contact/health     # -> {"ok":true}
```

**4. Route it through nginx** — the site's server block already proxies `/api/`
to this service (see `deploy/nginx-opsintels.conf`). Reload nginx:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Submit the form on `https://opsintels.com` — it should say "your message has been
sent," and the email lands at `CONTACT_TO`, with the sender on `Reply-To`.

## Notes

- **Spam:** a hidden honeypot field (`company`) is dropped server-side. Add rate
  limiting at nginx if you get abuse.
- **Logs:** `journalctl -u opsintel-contact -f`.
- **Security:** `.env` holds the SMTP password — keep it `chmod 600` and never
  commit it (`.gitignore` already excludes `.env`).
