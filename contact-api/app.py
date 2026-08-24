"""OpsIntel contact-form handler.

A tiny Flask endpoint the static site POSTs to, so a message is emailed
server-side — no mail-app popup, and the recipient address never appears in the
browser. Delivery is over SMTP (Amazon SES SMTP, or any provider), configured
entirely by environment variables; nothing sensitive lives in this file.

    POST /api/contact   {name, email, phone, message, company?}  ->  {"ok": true}

`company` is a honeypot: real users leave it blank, so a filled value is dropped.
Run behind nginx on 127.0.0.1 (see opsintel-contact.service).
"""

from __future__ import annotations

import os
import smtplib
import ssl
from email.message import EmailMessage

from flask import Flask, jsonify, request

app = Flask(__name__)

TO = os.environ.get("CONTACT_TO", "bikash.sen@opsintels.com")
FROM = os.environ.get("CONTACT_FROM", "bikash.sen@opsintels.com")
SMTP_HOST = os.environ.get("SMTP_HOST", "smtpout.secureserver.net")
SMTP_PORT = int(os.environ.get("SMTP_PORT", "465"))
SMTP_USER = os.environ.get("SMTP_USER", "")
SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD", "")
USE_STARTTLS = os.environ.get("SMTP_STARTTLS", "true").lower() not in ("false", "0", "no")


def _send(name: str, email: str, phone: str, message: str) -> None:
    """Send one contact message. Raises on any SMTP/config failure."""
    if not SMTP_HOST:
        raise RuntimeError("SMTP is not configured (set SMTP_HOST etc.)")

    body = (
        "New contact from the OpsIntel site:\n\n"
        f"Name:  {name}\n"
        f"Email: {email}\n"
        f"Phone: {phone or '—'}\n\n"
        f"{message or '(no message)'}\n"
    )
    msg = EmailMessage()
    msg["Subject"] = f"OpsIntel contact — {name}"
    msg["From"] = FROM
    msg["To"] = TO
    msg["Reply-To"] = email  # so a reply goes straight to the sender
    msg.set_content(body)

    context = ssl.create_default_context()
    if SMTP_PORT == 465:
        with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, context=context, timeout=15) as s:
            if SMTP_USER:
                s.login(SMTP_USER, SMTP_PASSWORD)
            s.send_message(msg)
    else:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15) as s:
            if USE_STARTTLS:
                s.starttls(context=context)
            if SMTP_USER:
                s.login(SMTP_USER, SMTP_PASSWORD)
            s.send_message(msg)


@app.post("/api/contact")
def contact():  # noqa: ANN201 - Flask view
    data = request.get_json(silent=True) or {}

    # Honeypot: silently accept and drop obvious bots.
    if (data.get("company") or "").strip():
        return jsonify({"ok": True})

    name = (data.get("name") or "").strip()
    email = (data.get("email") or "").strip()
    phone = (data.get("phone") or "").strip()
    message = (data.get("message") or "").strip()

    if not name or not email or "@" not in email:
        return jsonify({"ok": False, "error": "A name and a valid email are required."}), 400
    if len(name) > 200 or len(email) > 320 or len(phone) > 60 or len(message) > 5000:
        return jsonify({"ok": False, "error": "One of the fields is too long."}), 400

    try:
        _send(name, email, phone, message)
    except Exception as exc:  # noqa: BLE001 - report a generic failure, log the detail
        app.logger.error("contact send failed: %s", exc)
        return jsonify({"ok": False, "error": "Could not send right now."}), 502

    return jsonify({"ok": True})


@app.get("/api/contact/health")
def health():  # noqa: ANN201
    return jsonify({"ok": True})


if __name__ == "__main__":
    # Local dev only; in production run under gunicorn (see the service unit).
    app.run(host="127.0.0.1", port=8100, debug=True)
