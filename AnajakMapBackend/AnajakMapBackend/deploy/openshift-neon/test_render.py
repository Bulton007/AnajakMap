import unittest
from render import render


class RenderingTest(unittest.TestCase):
    def test_separate_schemas_and_gateway_only_route(self):
        items = render("test-project", "quay.io/example", "commit-123")["items"]
        deployments = [i for i in items if i["kind"] == "Deployment"]
        self.assertEqual(len(deployments), 9)
        schemas = set()
        for item in deployments:
            pod = item["spec"]["template"]["spec"]
            self.assertFalse(pod["automountServiceAccountToken"])
            container = pod["containers"][0]
            self.assertTrue(container["securityContext"]["readOnlyRootFilesystem"])
            values = {e["name"]: e["value"] for e in container["env"]}
            self.assertEqual(values["SPRING_PROFILES_ACTIVE"], "prod,neon")
            schemas.add(values["DB_SCHEMA"])
        self.assertEqual(len(schemas), 9)
        routes = [i for i in items if i["kind"] == "Route"]
        self.assertEqual(len(routes), 1)
        self.assertEqual(routes[0]["spec"]["path"], "/api/v1")
        self.assertEqual(routes[0]["spec"]["tls"]["insecureEdgeTerminationPolicy"], "Redirect")
        self.assertFalse(any(i["kind"] == "Secret" for i in items))

    def test_migrations_use_owner_secret_and_never_restart(self):
        items = render("test-project", "quay.io/example", "commit-123", "migrations")["items"]
        self.assertEqual(len(items), 9)
        for item in items:
            self.assertEqual(item["kind"], "Job")
            pod = item["spec"]["template"]["spec"]
            self.assertEqual(pod["restartPolicy"], "Never")
            self.assertTrue(pod["containers"][0]["envFrom"][1]["secretRef"]["name"].endswith("-migration"))

    def test_rejects_mutable_tag_or_credential_prefix(self):
        with self.assertRaises(ValueError): render("test", "quay.io/example", "latest")
        with self.assertRaises(ValueError): render("test", "https://user:password@example.test", "v1")


if __name__ == "__main__": unittest.main()
