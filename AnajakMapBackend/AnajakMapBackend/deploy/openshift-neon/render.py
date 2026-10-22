"""Render credential-free OpenShift resources. Never connects to a cluster."""
import argparse
import json
import re

SERVICES = ("identity", "trip", "ai-guide", "discovery", "expense",
            "reservation", "journal", "notification", "gateway")


def render(namespace, image_prefix, image_tag, stage="app"):
    if not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", namespace):
        raise ValueError("Invalid namespace")
    if not re.fullmatch(r"[a-z0-9][a-z0-9.\-/:]*[a-z0-9]", image_prefix):
        raise ValueError("Use a registry/repository prefix without credentials")
    if image_tag == "latest" or not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}", image_tag):
        raise ValueError("Use an explicit release/commit image tag")
    if stage not in ("app", "migrations"):
        raise ValueError("Unknown deployment stage")
    resources = []
    security = {"allowPrivilegeEscalation": False, "readOnlyRootFilesystem": True,
                "capabilities": {"drop": ["ALL"]}}
    for index, service in enumerate(SERVICES):
        name = service + "-service"
        schema = service.replace("-", "_")
        port = 8081 + index
        labels = {"app": name, "app.kubernetes.io/part-of": "anajakmap"}
        metadata = {"name": name, "namespace": namespace, "labels": labels}
        env = [{"name": "SPRING_PROFILES_ACTIVE", "value": "prod,neon"},
               {"name": "DB_SCHEMA", "value": schema},
               {"name": "DB_MIGRATION_LOCATION", "value": "classpath:db/postgresql"},
               {"name": "SPRING_FLYWAY_ENABLED", "value": "false"},
               {"name": "SPRINGDOC_API_DOCS_ENABLED", "value": "false"},
               {"name": "SPRINGDOC_SWAGGER_UI_ENABLED", "value": "false"},
               {"name": "MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE", "value": "health"},
               {"name": "LOG_PATH", "value": "/tmp/logs"},
               {"name": "JAVA_TOOL_OPTIONS", "value": "-XX:ActiveProcessorCount=2"}]
        migration = stage == "migrations"
        if migration:
            env.append({"name": "MIGRATE_ONLY", "value": "true"})
        container = {"name": "app", "image": f"{image_prefix}/{name}:{image_tag}",
                     "imagePullPolicy": "Always", "securityContext": security,
                     "env": env,
                     "envFrom": [{"secretRef": {"name": "anajak-shared"}},
                                 {"secretRef": {"name": service + ("-migration" if migration else "-runtime")}}],
                     "resources": {"requests": {"cpu": "100m", "memory": "384Mi"},
                                   "limits": {"cpu": "1", "memory": "768Mi"}},
                     "volumeMounts": [{"name": "tmp", "mountPath": "/tmp"}]}
        pod = {"automountServiceAccountToken": False,
               "securityContext": {"runAsNonRoot": True, "seccompProfile": {"type": "RuntimeDefault"}},
               "containers": [container],
               "volumes": [{"name": "tmp", "emptyDir": {"sizeLimit": "128Mi"}}]}
        if migration:
            pod["restartPolicy"] = "Never"
            resources.append({"apiVersion": "batch/v1", "kind": "Job",
                              "metadata": {**metadata, "name": service + "-migrate"},
                              "spec": {"backoffLimit": 1, "activeDeadlineSeconds": 600,
                                       "template": {"metadata": {"labels": labels}, "spec": pod}}})
        else:
            container["ports"] = [{"name": "http", "containerPort": port}]
            for probe, path in (("startupProbe", "liveness"), ("livenessProbe", "liveness"),
                                ("readinessProbe", "readiness")):
                container[probe] = {"httpGet": {"path": "/actuator/health/" + path, "port": "http"},
                                    "periodSeconds": 5 if probe == "startupProbe" else 10,
                                    "timeoutSeconds": 3, "failureThreshold": 60 if probe == "startupProbe" else 3}
            resources.extend([
                {"apiVersion": "apps/v1", "kind": "Deployment", "metadata": metadata,
                 "spec": {"replicas": 1, "revisionHistoryLimit": 3,
                          "selector": {"matchLabels": {"app": name}},
                          "template": {"metadata": {"labels": labels}, "spec": pod}}},
                {"apiVersion": "v1", "kind": "Service", "metadata": metadata,
                 "spec": {"selector": {"app": name}, "ports": [{"name": "http", "port": port, "targetPort": "http"}]}}
            ])
    if stage == "app":
        resources.append({"apiVersion": "route.openshift.io/v1", "kind": "Route",
                          "metadata": {"name": "anajak-api", "namespace": namespace},
                          "spec": {"path": "/api/v1", "to": {"kind": "Service", "name": "gateway-service"},
                                   "port": {"targetPort": "http"},
                                   "tls": {"termination": "edge", "insecureEdgeTerminationPolicy": "Redirect"}}})
    return {"apiVersion": "v1", "kind": "List", "items": resources}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--namespace", required=True)
    parser.add_argument("--image-prefix", required=True)
    parser.add_argument("--image-tag", required=True)
    parser.add_argument("--stage", choices=("app", "migrations"), default="app")
    args = parser.parse_args()
    print(json.dumps(render(args.namespace, args.image_prefix, args.image_tag, args.stage), indent=2))
