# AnajakMap

Cambodia-focused AI travel companion with a Flutter Android/iOS application and a Spring Boot backend using Oracle, Redis, RabbitMQ and object storage.

- [Flutter application and local run instructions](flutter_app/README.md)
- [Authentication and Gmail setup](flutter_app/AUTH_SETUP.md)
- [Integration report and feature coverage](INTEGRATION.md)
- [Backend](AnajakMapBackend/AnajakMapBackend)
- [Kubernetes deployment instructions](AnajakMapBackend/AnajakMapBackend/deploy/kubernetes/README.md)
- [Production readiness and remaining work](PRODUCTION_STATUS.md)
- [Production server configuration](AnajakMapBackend/AnajakMapBackend/deploy/production/README.md)
- [Signed mobile release instructions](flutter_app/PRODUCTION_RELEASE.md)

Development travel providers are explicitly labelled fixtures. Gmail delivery, real legal URLs, live provider credentials and other outstanding production configuration are documented in the setup guides. Credentials and generated build files are excluded from version control.

## Windows laptop startup

Install Docker Desktop with its Linux engine and Git, clone this repository,
then double-click `Start Backend.cmd`. The launcher starts Docker, builds and
initializes a fresh setup when needed, then runs Nginx and the public test tunnel.
Windows PowerShell 5.1 is supported; installing `pwsh` is unnecessary.
See the [laptop hosting guide](AnajakMapBackend/AnajakMapBackend/deploy/laptop/README.md).
Restore your original `.env` and database/media backups to preserve existing data.
