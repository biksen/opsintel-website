# opsintel-website

The public one-page site for **opsintels.com** — an OpsIntels landing page with a
section for the flagship product, **Fulcrum**, and a link to the live app at
`https://fulcrum.opsintels.com`.

It is a single self-contained `index.html` (no build step): fonts come from Google
Fonts, everything else is inline. Meant to run on a small, **always-on** host so the
front door stays up even when the Fulcrum EC2 instance is stopped to save costs.

## The Fulcrum "is it up?" behaviour

The Fulcrum launch buttons don't link blindly. On load — and again on click — the
page probes `https://fulcrum.opsintels.com/healthz` with a short-timeout `no-cors`
`fetch`:

- **Reachable** → the status pill shows `online` and the button opens the app.
- **Unreachable** (instance stopped) → a status panel appears:
  _"The Fulcrum application is down right now"_, with **Check again** and a contact
  link — never a dead browser error.

> Note: the probe distinguishes "instance up" from "instance stopped". If the
> instance is running but the app itself is failing (e.g. nginx returns 5xx), the
> probe still reads `online` and the user lands on Fulcrum's own error page.

## Files

| File | What it is |
|------|------------|
| `index.html` | The entire site (markup + styles + probe script) |
| `favicon.svg` | Brand mark |
| `deploy/nginx-opsintels.conf` | Sample nginx server block |
| `deploy/setup.sh` | One-shot: install nginx, publish the site, get HTTPS |

## Deploy on the always-on (free-tier) EC2

**Prerequisites**

1. An A record for `opsintels.com` (and `www`) pointing at this instance's public
   IP / Elastic IP.
2. Security group inbound: **TCP 80 and 443** open to `0.0.0.0/0`.

**One-shot**

```bash
git clone https://github.com/biksen/opsintel-website.git
cd opsintel-website
sudo FULCRUM_LE_EMAIL=you@example.com ./deploy/setup.sh
```

That installs nginx, copies the site to `/var/www/opsintels`, writes the server
block, and obtains a Let's Encrypt certificate for `opsintels.com` + `www`.

**Updating the site later**

```bash
cd opsintel-website && git pull
sudo cp index.html favicon.svg /var/www/opsintels/
```

## Local preview

```bash
python3 -m http.server 8080     # then open http://localhost:8080
```
