"""Sends sign-in emails (verification and password reset codes)."""

import asyncio
import logging
import smtplib
from email.message import EmailMessage

from .config import get_settings

log = logging.getLogger("codenote.mail")


async def send_code(to: str, purpose: str, code: str) -> None:
    s = get_settings()
    what = "confirm your email" if purpose == "verify" else "reset your password"
    subject = f"Your CodeNote code: {code}"
    text = (
        f"Your code to {what} is:\n\n    {code}\n\n"
        "It works for 15 minutes. If you didn't ask for it, you can ignore this email."
    )
    if not s.smtp_enabled:
        log.warning("No SMTP set up. Code for %s (%s): %s", to, purpose, code)
        return

    def work() -> None:
        msg = EmailMessage()
        msg["From"] = s.smtp_from
        msg["To"] = to
        msg["Subject"] = subject
        msg.set_content(text)
        with smtplib.SMTP(s.smtp_host, s.smtp_port, timeout=20) as smtp:
            smtp.starttls()
            if s.smtp_user:
                smtp.login(s.smtp_user, s.smtp_password)
            smtp.send_message(msg)

    try:
        await asyncio.to_thread(work)
    except Exception as e:
        log.error("Couldn't send email to %s: %s", to, e)
