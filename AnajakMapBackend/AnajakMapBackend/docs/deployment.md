The repository supplies a production Dockerfile, a local-jar Dockerfile, Compose infrastructure, separate migration execution, restricted runtime database grants, and OpenShift manifests. The application image runs with a non-root default user, group-writable application/log directories, and no hard-coded OpenShift UID. Deployment security contexts drop capabilities, disallow privilege escalation and use a read-only root filesystem with writable temporary/log volumes.

For local development, `scripts/start-local.sh` is the supported complete flow. It initializes schema owners, runs each jar with MIGRATE_ONLY=true, grants each <SCHEMA>_APP user access only to its own schema, then disables Flyway and sets CURRENT_SCHEMA for runtime connections. `compose.runtime.yml` preserves these restrictions on restart. Schema owner passwords stay in Oracle's initialization environment and migration containers, not runtime service containers. The official Oracle override was used in local validation; gvenzl's standard image has the corresponding initialization directory and healthcheck configured.

For OpenShift, first build/tag/push the nine images to the project's image registry, provision an internal Oracle database, create schema owners, and install production Redis/RabbitMQ/S3 storage. Oracle is intentionally an internal external dependency rather than an application-managed privileged pod: use an approved DBA/operator installation and backup policy. It receives no public Route. The supplied single-node Redis/RabbitMQ/MinIO StatefulSets with PVCs are development/reference resources; verify their image support with your cluster's restricted SCC or use supported operators. Cluster operator resources are not installed automatically.

Create the anajakmap namespace and per-service ConfigMaps. Set actual internal Oracle URLs and independently scoped provider URLs. Supply <service>-migration-secrets containing DB_PASSWORD for the schema owner. Apply `migrations.yml`, wait for all Jobs to succeed, then grant runtime table privileges using `scripts/grant-runtime.sh` adapted for your DBA connection (its local form uses sqlplus / as sysdba inside Oracle). Migration Jobs must be renamed for subsequent releases so completed Jobs do not mask new migrations.

Supply <service>-service-secrets containing DB_PASSWORD for its restricted <SCHEMA>_APP user, JWT_PUBLIC_KEY, DATA_ENCRYPTION_KEY, SERVICE_TOKEN, REDIS_PASSWORD, RABBIT_USER, RABBIT_PASSWORD, OBJECT_ACCESS_KEY and OBJECT_SECRET_KEY. Only Identity receives JWT_PRIVATE_KEY. AI Guide, Discovery and Notification receive their own PROVIDER_URL/KEY. Identity receives MAIL_PROVIDER_URL/KEY; Expense receives CURRENCY_PROVIDER_URL/KEY; Trip optionally receives CALENDAR_PROVIDER_URL/KEY. JWT keys are base64 DER: public X.509 and private PKCS8. DATA_ENCRYPTION_KEY is base64 for 32 random bytes. Use a secrets manager; no real Secret objects are committed.

The reference infrastructure resources use infrastructure-secrets with REDIS_PASSWORD, RABBIT_USER/PASSWORD and OBJECT_ACCESS_KEY/SECRET_KEY. Create the private anajak-media bucket before launching services. Runtime service ConfigMaps disable Flyway, set their CURRENT_SCHEMA, and select production. Missing required provider configuration prevents the affected service from starting; it never yields mock travel facts.

Apply application resources only after successful migrations and permissions:

```sh
oc apply -f deploy/openshift/namespace.yml
# Provision secrets/configuration and run the migration Jobs first.
oc apply -k deploy/openshift
oc rollout status deployment/gateway-service -n anajakmap
```

The Route redirects HTTP to HTTPS. NetworkPolicies allow ingress from project pods and the OpenShift ingress namespace only to Gateway. No public routes exist for Oracle, Redis or RabbitMQ. Before production traffic, configure mTLS using the cluster's service mesh (or TLS service endpoints), TLS/authentication for data services, appropriate egress restrictions, provider credentials, backups, private object-storage encryption and retention. The supplied reference configuration's internal HTTP is for local/reference operation; it is not evidence of a verified production mTLS installation.

Each service's logs use a persistent claim and stdout. Enable the cluster's supported log collector/ClusterLogForwarder for stdout to central storage; rotating PVC files preserve local diagnostic logs across replacement. The manifests include startup/readiness/liveness probes and resource limits. Prometheus metrics are exposed at /actuator/prometheus and require a JWT. Configure cluster monitoring authentication rather than exposing metrics anonymously.

Manifests have not been applied to a real OpenShift cluster. Storage classes, SCC behavior for infrastructure images, registry pull access, mesh configuration, provider availability, forwarding and ingress host selection require validation in the target cluster. No paid or external environment was contacted for deployment.
