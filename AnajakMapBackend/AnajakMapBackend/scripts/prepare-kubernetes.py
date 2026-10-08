"""Render a portable LOCAL development overlay; never contacts a cluster."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
source = root / 'deploy/openshift'
target = root / 'deploy/kubernetes'
target.mkdir(parents=True, exist_ok=True)
services = ['identity', 'trip', 'ai-guide', 'discovery', 'expense', 'reservation', 'journal', 'notification', 'gateway']
resources = ['namespace.yml', 'oracle.yml', 'redis.yml', 'rabbitmq.yml', 'minio.yml', 'object-init.yml']
for name in [f'{s}-service.yml' for s in services] + ['redis.yml', 'rabbitmq.yml', 'minio.yml', 'migrations.yml']:
    text = (source / name).read_text()
    text = text.replace('namespace: anajakmap', 'namespace: anajakmap-local')
    text = text.replace('image-registry.openshift-image-registry.svc:5000/anajakmap/', 'anajakmap-').replace(':0.1.0', ':latest')
    text = text.replace('SPRING_PROFILES_ACTIVE: production', 'SPRING_PROFILES_ACTIVE: dev')
    text = text.replace('oracle.internal:1521', 'oracle:1521')
    text = text.replace('quay.io/minio/minio:RELEASE.2025-04-22T22-12-26Z','anajakmap/minio:local-2025-04-22')
    text = text.replace('          image:', '          imagePullPolicy: IfNotPresent\n          image:')
    if name.endswith('-service.yml'):
        text = text.replace('replicas: 1', 'replicas: 0')  # Explicitly scale after migrations + runtime grants.
        text = text.replace('      securityContext:\n        seccompProfile:', '      securityContext:\n        fsGroup: 1001\n        seccompProfile:')
        resources.append(name)
    if name == 'minio.yml':
        text=text.replace('      automountServiceAccountToken:', '      securityContext:\n        fsGroup: 1001\n      automountServiceAccountToken:')
    if name == 'gateway-service.yml':
        text += '  CORS_ALLOWED_ORIGINS: http://localhost:7777,http://127.0.0.1:7777\n'
    (target / name).write_text(text)
scripts = target / 'oracle-scripts'
scripts.mkdir(exist_ok=True)
for src, name in [(root/'deploy/oracle/01-schemas.sh','01-schemas.sh'),(root/'scripts/grant-runtime.sh','grant-runtime.sh')]:
    (scripts/name).write_text(src.read_text())
(target/'kustomization.yaml').write_text('apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\nresources:\n'+''.join(f'  - {r}\n' for r in resources)+'configMapGenerator:\n  - name: oracle-scripts\n    namespace: anajakmap-local\n    files:\n      - oracle-scripts/01-schemas.sh\n      - oracle-scripts/grant-runtime.sh\ngeneratorOptions:\n  disableNameSuffixHash: true\n')
print('Rendered deploy/kubernetes. Application replicas remain zero until migrations and grants finish.')
