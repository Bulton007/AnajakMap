import re
import unittest
from preflight import ROOT, validate


class PreflightTest(unittest.TestCase):
    def valid(self):
        keys = set(re.findall(r"\$\{([A-Z_]+):\?", (ROOT / "compose.yml").read_text()))
        data = {k: "a" * 32 for k in keys}
        for key in keys:
            if key.endswith("_URL"):
                data[key] = "https://service.example.com"
        data.update(API_DOMAIN="api.example.com", IMAGE_TAG="release-2026-10-20",
                    DB_URL="jdbc:oracle:thin:@db:1521/PROD",
                    GMAIL_USERNAME="sender@example.com", GMAIL_APP_PASSWORD="test-only")
        return data

    def test_complete_configuration(self):
        self.assertEqual([], validate(self.valid()))

    def test_missing_configuration_and_development(self):
        self.assertTrue(validate({}))
        data = self.valid()
        data.update(API_DOMAIN="localhost", IMAGE_TAG="latest", SPRING_PROFILES_ACTIVE="dev",
                    OBJECT_URL="http://storage", SERVICE_TOKEN="short")
        result = "\n".join(validate(data))
        for key in ("API_DOMAIN", "IMAGE_TAG", "SPRING_PROFILES_ACTIVE", "OBJECT_URL", "SERVICE_TOKEN"):
            self.assertIn(key, result)
        self.assertNotIn("test-only", result)

    def test_private_hosts_and_credentials(self):
        data = self.valid()
        data.update(API_DOMAIN="192.168.1.1", AUTH_TERMS_URL="https://user:private@legal.example.com")
        result = "\n".join(validate(data))
        self.assertIn("API_DOMAIN", result)
        self.assertIn("AUTH_TERMS_URL", result)
        self.assertNotIn("private@", result)


if __name__ == "__main__":
    unittest.main()
