# Nginx laptop hosting — temporary public testing

Traffic: phone → Cloudflare HTTPS tunnel → Nginx → gateway → private services.
Your Oracle database, Redis, RabbitMQ and object storage stay in Docker. This
does not deploy to OpenShift or migrate the live local data to Neon.

## Start

Double-click `C:\anajak_map\Start Backend.cmd`. It starts Docker Desktop if
needed, waits for the engine, initializes/builds a fresh PC when required,
starts the backend/Nginx/public test tunnel,
prints the current public URL, updates Flutter's local config, and verifies the
proxy. The window stays open so errors and the URL remain visible. Closing that
window after successful startup does not stop the Docker containers.

PowerShell 7 (`pwsh`) is not required. Windows' built-in `powershell.exe` works;
first-run keys are generated securely inside the same JDK container used by the
backend build. Install Docker Desktop (Linux engine/WSL 2) and Git, clone the
repository, then double-click the launcher. Initial downloads/builds take longer.
Existing `.env` files are never overwritten. If a database volume exists without
its `.env`, initialization stops and asks for the original credentials.

Docker Desktop must be running. From the backend root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-laptop.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-laptop.ps1
# Starts services, waits for auth readiness, then starts the temporary tunnel:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-laptop.ps1 -TemporaryPublicUrl
```

This reuses the initialized local stack and volumes. It does not initialize a
fresh database, rebuild images or run schema migrations. For a new setup, first
use `scripts/start-local.ps1` as described in the backend README.

Nginx binds only `http://127.0.0.1:8090` (or `LAPTOP_NGINX_PORT`). The existing USB
gateway remains on localhost port 8080. No router forwarding or inbound firewall
rule is required. Only `/api/v1/*` reaches the gateway. `/healthz` reports Nginx
alone, not backend readiness; actuator, Swagger and internal paths return 404.
Authorization stays enforced by Spring. Requests allow up to 11MiB to match the
existing upload envelope. Logs omit query strings, request bodies and credentials.
Nginx discards client-supplied Forwarded headers and replaces X-Forwarded-For;
per-client rate-limit attribution through the tunnel still needs a trusted
Cloudflare client-IP policy before production scaling.

The overlay enables `unless-stopped` restarts for persistent containers and caps
Docker log sizes. Practice/simulated RPG rewards are disabled. Other local
fixture providers remain honestly labeled in the app: this is a testing stack,
not the final production/Play Store backend. Use dedicated test accounts and
review the outstanding work in `PRODUCTION_STATUS.md` before public launch.

## Connect Flutter

Use the current tunnel HTTPS origin followed by `/api/v1/`. A local config is
written as `flutter_app/config/connected.public.local.json` for this run; it has
no secrets. From `flutter_app`:

```powershell
flutter run --dart-define-from-file=config/connected.public.local.json
# Or build an APK to install without USB forwarding:
flutter build apk --debug --target-platform android-arm64 --dart-define-from-file=config/connected.public.local.json
```

Run `scripts/test-laptop.ps1 -BaseUrl https://YOUR_CURRENT_TUNNEL_HOST` to check the
public route. Expected statuses: auth config 200, profile 401, internal paths
404. This does not sign into accounts, send mail, use AI quota or mutate trips.

Verified in this setup: all nine private readiness endpoints returned `UP`, and
the public HTTPS checks returned the expected statuses. A debug APK was built
with the current public URL, green theme and green-and-gold launcher icon.
Samsung was disconnected, so that build has not yet been installed on the phone.

## Keep the laptop available

- Keep it plugged in, awake, connected to the internet, and Docker running.
  Plugged-in sleep and hibernation were already set to Never during setup.
- Docker Desktop already has a Windows sign-in startup entry on this laptop.
  Windows sign-in is still required after reboot; Docker Desktop is not a
  pre-login Windows server service. Do not enable automatic Windows login just
  to host the app. Keep normal security updates and arrange downtime.
- Do not quit Docker, close the lid if that causes sleep, or stop the tunnel.
  The screen may turn off without putting the computer to sleep.
- Back up Oracle and private media independently; a restart policy is not a
  backup or an uptime guarantee. Preserve application encryption/signing keys.
- A stopped container stays stopped with `unless-stopped`; rerun the start
  command to resume it. Docker Desktop resource saving/sleep behavior should be
  checked when testing overnight availability.

Quick Tunnels have no uptime guarantee and generate a different hostname on each
new tunnel run. A restart can therefore invalidate the app's configured URL.
This cannot be called a stable 24/7 production endpoint. For the final release,
use a domain and named Cloudflare Tunnel, or persistent hosted infrastructure.
Do not publish the Play Store app with a `trycloudflare.com` address.

Stop public access while keeping the local backend running:

```powershell
docker stop anajakmap-laptop-tunnel-1
```

Do not run `docker compose down -v`: that deletes database/media volumes.

References: [Cloudflare Quick Tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/),
[Docker startup settings](https://docs.docker.com/desktop/settings-and-maintenance/settings/),
[Nginx proxy module](https://nginx.org/en/docs/http/ngx_http_proxy_module.html).
