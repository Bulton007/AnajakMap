# Local Kubernetes deployment

This development deployment connects nine Spring services to Oracle, Redis,
RabbitMQ and the local S3-compatible media service. It uses **development provider
fixtures**, not live travel/AI facts. It does not purchase reservations.

These manifests have not been applied to the current OpenShift context. Choose a
dedicated local Docker Desktop or kind context explicitly before applying them.
Allow roughly 12–16 GB Docker memory, disk for Oracle and a default StorageClass.
The Oracle PVC is persistent; deleting it loses the database.

1. Run `pwsh scripts/start-local.ps1` to build/test images, or build the same images
   separately. Docker Compose and Kubernetes run separate databases; they do not
   share their volumes. Avoid running both stacks on a small machine.
2. Render portable files: `python scripts/prepare-kubernetes.py`. Inspect them with
   `kubectl kustomize deploy/kubernetes`. This command does not contact a cluster.
3. Prepare local secrets: `python scripts/kubernetes-secrets.py`. The generated
   `.local/kubernetes-secrets.json` is ignored and must not be committed or shared.
4. With an explicitly chosen local context, apply `namespace.yml`, the secret
   manifest, and `kubectl --context YOUR_LOCAL_CONTEXT apply -k deploy/kubernetes`.
   Application replicas initially remain **zero**. Load the nine
   `anajakmap-SERVICE-service:latest` images and `anajakmap/minio:local-2025-04-22`
   / `anajakmap/mc:local-2025-04-16` into kind first if using kind; Docker Desktop
   uses its local image store. Pin registry digests for a shared environment.
5. Wait for `statefulset/oracle`, Redis, RabbitMQ and MinIO to be ready and
   `job/object-init` to complete. Oracle's initial setup creates isolated owner
   schemas. On an existing database run `bash /opt/oracle/scripts/setup/01-schemas.sh`
   in `oracle-0` explicitly to create any missing schemas.
6. Apply `deploy/kubernetes/migrations.yml`; wait for all nine migration Jobs to
   complete successfully. They use owner credentials. A new migration deployment
   needs a new Job name or deliberate replacement of the completed Jobs.
7. Copy `scripts/grant-runtime.sh` to `oracle-0:/tmp/grant-runtime.sh` with
   `kubectl --context YOUR_LOCAL_CONTEXT -n anajakmap-local cp ...`, then execute
   `bash /tmp/grant-runtime.sh` in that pod. This creates restricted `_APP` users
   and grants DML on the migrated tables. Runtime pods do not own their schemas.
8. Scale each of the nine `*-service` deployments to one replica. Check readiness.
9. Forward the gateway only:
   `kubectl --context YOUR_LOCAL_CONTEXT -n anajakmap-local port-forward service/gateway-service 8080:8089`.
   Run Flutter with `config/connected.web.json` or Android's emulator configuration.

There is no public ingress by default. For production, retain the existing
`deploy/openshift` manifests as a starting point, supply maintained storage,
provider adapters, HTTPS, backup/restore procedures and environment-specific
secrets. Do not reuse local development credentials. The MinIO source rebuild
preserves the supplied backend's pinned legacy versions for local compatibility;
it is not a maintained production storage recommendation.
