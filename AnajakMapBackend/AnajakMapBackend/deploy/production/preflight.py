"""Offline configuration checks. Never prints secret values or deploys resources."""
import argparse
import ipaddress
import re
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent


def read_env(path):
    values = {}
    for line in Path(path).read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError("Expected KEY=value lines")
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip("'\"")
    return values


def public_host(host):
    if not host or "." not in host or host.lower().endswith((".test", ".example", ".invalid", ".localhost", ".local")):
        return False
    try:
        return ipaddress.ip_address(host).is_global
    except ValueError:
        return bool(re.fullmatch(r"[a-zA-Z0-9.-]+", host))


def validate(values):
    errors = []
    required = set(re.findall(r"\$\{([A-Z_]+):\?", (ROOT / "compose.yml").read_text()))
    for key in sorted(required):
        value = values.get(key, "")
        if not value or re.search(r"replace|change_me|your[_-]|<|>", value, re.I):
            errors.append(f"{key}: required, non-placeholder value missing")
    domain = values.get("API_DOMAIN", "")
    if not public_host(domain) or ":" in domain or "/" in domain:
        errors.append("API_DOMAIN: use a public DNS hostname without scheme or path")
    for key in ["AUTH_TERMS_URL", "AUTH_PRIVACY_URL", "OBJECT_URL",
                "AI_PROVIDER_URL", "DISCOVERY_PROVIDER_URL", "CURRENCY_PROVIDER_URL",
                "PUSH_PROVIDER_URL", "PHOTON_BASE_URL"]:
        uri = urlsplit(values.get(key, ""))
        if uri.scheme != "https" or not uri.hostname or uri.username or uri.password or uri.fragment:
            errors.append(f"{key}: HTTPS URL without embedded credentials required")
    if not values.get("DB_URL", "").startswith("jdbc:oracle:thin:@"):
        errors.append("DB_URL: Oracle JDBC connection required")
    if values.get("IMAGE_TAG", "").lower() in ("latest", "dev", "test", ""):
        errors.append("IMAGE_TAG: use an immutable release identifier")
    for key in required:
        if key.endswith("_PASSWORD") or key == "SERVICE_TOKEN":
            if len(values.get(key, "")) < 24:
                errors.append(f"{key}: use at least 24 random characters")
    gmail = values.get("GMAIL_USERNAME") and values.get("GMAIL_APP_PASSWORD")
    provider = values.get("MAIL_PROVIDER_URL") and values.get("MAIL_PROVIDER_KEY")
    if not (gmail or provider):
        errors.append("Email: configure Gmail sender/app password or mail provider URL/key")
    if provider:
        uri = urlsplit(values["MAIL_PROVIDER_URL"])
        if uri.scheme != "https" or not uri.hostname or uri.username or uri.password:
            errors.append("MAIL_PROVIDER_URL: HTTPS without embedded credentials required")
    if any(v in values.get("SPRING_PROFILES_ACTIVE", "").split(",") for v in ("dev", "test")):
        errors.append("SPRING_PROFILES_ACTIVE: development profiles are prohibited")
    return errors


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", required=True)
    args = parser.parse_args()
    try:
        failures = validate(read_env(args.env_file))
    except (OSError, ValueError):
        failures = ["Could not read configuration; use a UTF-8 KEY=value environment file."]
    for failure in failures:
        print(f"BLOCKED: {failure}")
    if failures:
        raise SystemExit(1)
    print("Configuration checks passed. Live providers, DNS, migrations, restore and device tests are still required.")
