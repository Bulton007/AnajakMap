"""Check local Gmail SMTP settings without logging credentials.

By default only authenticates. --send-test sends one message to the sender's
own mailbox. Reads the ignored backend .env; never changes it.
"""
import argparse
from email.message import EmailMessage
from pathlib import Path
import smtplib
import ssl
import sys


def settings(path):
    result = {}
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        key, separator, value = line.partition("=")
        key = key.strip()
        if not separator or key not in ("GMAIL_USERNAME", "GMAIL_APP_PASSWORD"):
            continue
        if key in result:
            raise ValueError("Duplicate Gmail setting in .env")
        value = value.strip()
        if value[:1] in ("'", '"'):
            if len(value) < 2 or value[-1] != value[0]:
                raise ValueError("Unclosed quote in Gmail setting")
            value = value[1:-1]
        result[key] = value
    if not all(result.get(key) for key in ("GMAIL_USERNAME", "GMAIL_APP_PASSWORD")):
        raise ValueError("Both Gmail settings are required in .env")
    if any(char.isspace() for char in result["GMAIL_APP_PASSWORD"]):
        raise ValueError("Remove display spaces from the Gmail app password in .env")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--send-test", action="store_true")
    args = parser.parse_args()
    try:
        config = settings(Path(__file__).resolve().parent.parent / ".env")
        sender = config["GMAIL_USERNAME"]
        with smtplib.SMTP("smtp.gmail.com", 587, timeout=20) as client:
            client.ehlo()
            client.starttls(context=ssl.create_default_context())
            client.ehlo()
            client.login(sender, config["GMAIL_APP_PASSWORD"])
            print("PASS: Gmail STARTTLS and SMTP authentication.")
            if args.send_test:
                message = EmailMessage()
                message["From"] = sender
                message["To"] = sender
                message["Subject"] = "AnajakMap sender connection test"
                message.set_content(
                    "Your AnajakMap backend SMTP credentials successfully sent this "
                    "test message. This is not an account verification email. "
                    "No password or verification code is included."
                )
                client.send_message(message)
                print("PASS: Gmail accepted one test message to the sender mailbox.")
                print("Check Inbox/Spam to confirm receipt; acceptance is not inbox delivery.")
        return 0
    except ValueError as error:
        print(f"Configuration error: {error}", file=sys.stderr)
    except smtplib.SMTPAuthenticationError:
        print("FAIL: Gmail rejected authentication. Check the account and generated app password.", file=sys.stderr)
    except Exception as error:
        # Provider responses and exception messages may contain private data.
        print(f"FAIL: SMTP check failed ({type(error).__name__}); no secrets logged.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
