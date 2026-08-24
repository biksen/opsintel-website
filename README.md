# opsintel-website

The public one-page site for **opsintels.com** — an OpsIntel landing page with a
section for the flagship product, **Fulcrum**, a live Fulcrum status indicator, and
a server-side contact form.

The site itself is a single self-contained `index.html` (no build step): fonts come
from Google Fonts, everything else is inline. Meant to run on a small, **always-on**
host so the front door stays up even when the Fulcrum EC2 instance is stopped to save
costs. The contact form is handled by a tiny Flask service (see `contact-api/`).

## The Fulcrum "is it up?" behaviour

The Fulcrum launch buttons don't link blindly. On load — and again on click — the
page probes `https://fulcrum.opsintels.com/` with a short-timeout `no-cors` `fetch`,
and a **Live / Offline** indicator sits under every "Explore Fulcrum" button:

- **Reachable** → the indicator shows `Live` and the button opens the app.
- **Unreachable** (instance stopped) → the indicator shows `Offline`, and clicking
  opens a status panel — _"The Fulcrum application is down right now"_ with
  **Check again** — never a dead browser error.

> Note: the probe distinguishes "instance up" from "instance stopped". If the
> instance is running but the app itself is failing (e.g. nginx returns 5xx), the
> probe still reads `online` and the user lands on Fulcrum's own error page.

## Contact form (server-side)

The form POSTs to `/api/contact`, which nginx proxies to a small Flask handler
that emails the submission — no mail-app popup, and the recipient address is only
on the server (never in the page, so no browser tooltip reveals it). Setup lives in
[`contact-api/`](contact-api/README.md).

## Files

| File | What it is |
|------|------------|
| `index.html` | The entire site (markup + styles + status/contact scripts) |
| `favicon.svg` | Brand mark |
| `contact-api/` | Flask contact-form handler + systemd unit + setup |
| `deploy/nginx-opsintels.conf` | nginx server block (static site + `/api/` proxy) |
| `deploy/setup.sh` | One-shot: install nginx, publish the site, get HTTPS |

## Deploy on the always-on (free-tier) EC2

**Prerequisites**

1. An A record for `opsintels.com` (and `www`) pointing at this instance's public
   IP / Elastic IP.
2. Security group inbound: **TCP 80 and 443** open to `0.0.0.0/0`.

**One command — everything (site + HTTPS + contact handler):**

```bash
git clone https://github.com/biksen/opsintel-website.git   # or: git pull
cd opsintel-website
sudo ./deploy.sh
```

`deploy.sh` publishes the site, sets up nginx + a Let's Encrypt certificate on the
first run, and installs/refreshes the contact handler (prompting for the SMTP
login + password). It's **idempotent** — re-run it after every `git pull`. Pass
`LE_EMAIL=…` (cert-expiry notices) and `SMTP_USER=… SMTP_PASSWORD=…` as env vars
to skip the prompts.

The individual `deploy/setup.sh` (site only) and `contact-api/setup.sh` (handler
only) are still available if you want to run a single part.

**Updating the site later**

```bash
cd opsintel-website && git pull
sudo cp index.html favicon.svg /var/www/opsintels/
```

## Local preview

```bash
python3 -m http.server 8080     # then open http://localhost:8080
```
