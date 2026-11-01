# Fresh backend for Flutter build 12

This is a separate backend installation with an empty database. It preserves the original `anajakmap` project's users, trips, game progress and Docker volumes. The fresh project is always named **anajakmap-v12** and has dedicated application images, network, Oracle, Redis, RabbitMQ and media volumes.

The included private configuration is already at:

```text
AnajakMapBackend\AnajakMapBackend\.env
```

New database passwords, session signing keys and encryption keys were generated for this installation. The locally configured Gmail sender and Gemini settings were copied privately. Do not put this ZIP, its `.env` or its extracted folder on GitHub or a public file share. Keep a secure backup of this exact `.env` together with the new database; the launcher never regenerates credentials or resets existing data.

## Start on your hosting PC

1. Extract the ZIP into a **new** ordinary folder, such as `C:\AnajakMap-v12-Fresh`. Do not extract it over the old hosting folder. Open the extracted folder; the CMD launchers must be directly inside it.
2. Open Docker Desktop and wait for its Linux engine. Use a recent Docker Desktop/Compose release supporting Compose `!override`. Windows PowerShell is sufficient; `pwsh`, Java and Maven do not need separate installation.
3. Double-click **Start Fresh Backend.cmd**. The first run downloads build dependencies/images, builds the current source, creates the new schemas and applies all nine services' migrations. Wait for readiness and authentication/proxy checks to pass.
4. Double-click **Check Fresh Backend.cmd**. The local API is `http://127.0.0.1:18090/api/v1/`; the full public auth configuration path is `http://127.0.0.1:18090/api/v1/auth/config`.
5. For internet access, close the **old ngrok tunnel window** yourself, then double-click **Start Fresh Public Backend.cmd**. The launcher refuses to take over a different running tunnel. It forwards the account-assigned address to this fresh backend on port 18090, with request inspection disabled.
6. If ngrok is not configured on this PC, run **Configure Ngrok.cmd** once and enter your account token only in its hidden local prompt. The ngrok account profile/token is not in this ZIP.

The fresh public base URL is already configured as:

```text
https://reaction-parched-grip.ngrok-free.dev/api/v1/
```

Use the ngrok account that owns that hostname. Flutter build 12 already uses this URL, so it does not need a URL change. The old backend services can remain running; only the public tunnel needs to point to the chosen backend. Keep the fresh public window, Docker, your PC and its internet connection running while testing.

**Old account credentials will not exist in the fresh database.** Sign out in Anajak Test if needed, create a new test account and verify the email you receive. Old sessions use different signing keys and will expire rather than silently access the new database. The fresh ZIP contains configuration and sources, not a transfer of old accounts/media/game history.

## Available controls

| Launcher | Action |
| --- | --- |
| Start Fresh Backend.cmd | Build when sources change, apply migrations, start the isolated backend and check readiness. |
| Start Fresh Public Backend.cmd | Perform local checks, then expose only the fresh Nginx port through the configured ngrok address. |
| Check Fresh Backend.cmd | Check anonymous API contracts and authentication boundaries without sending mail or AI requests. |
| Check Fresh AI.cmd | Inspect only the fresh AI container's provider/configuration/readiness facts. It does not call Google. |
| Stop Fresh Backend.cmd | Stop only the fresh project's services; retain its data and credentials. Close ngrok separately. |
| Configure Ngrok.cmd | Save this Windows user's ngrok account token privately. |

To restart, use **Stop Fresh Backend.cmd**, then **Start Fresh Backend.cmd**. No launcher deletes volumes. Use only this bundle's fresh root launchers; generic internal legacy update scripts are not the supported workflow for this isolated project.

## Configuration and feature boundaries

The inner `.env` contains the provider settings. Changes to Gmail or Gemini must be made locally on the hosting PC, never pasted into chat. Keep the fresh database/session credentials and project/port settings unchanged. Running **Start Fresh Backend.cmd** again applies configuration changes and recreates affected services after validating the existing database configuration.

- Authentication uses the actual email verification and password recovery contracts. Email delivery still depends on Gmail accepting the configured sender/App Password; no code is displayed as a successful inbox delivery.
- Gemini is configured server-side. Real model requests, quota and availability are external dependencies; configured/readiness flags do not prove every request will succeed. Google/Apple sign-in and receipt/reservation AI extraction remain unavailable where their actual integration is missing.
- Driving routes use the road-geometry contract Flutter expects. The public OSRM test router is enabled under the development profile; it is a bounded, best-effort test service. It does not provide live traffic or bicycle/transit routing.
- Explore photos use the current licensed-photo contract. Missing photos retain an honest fallback.
- RPG field and practice realms retain server-owned inventory, battles and rewards; practice does not become field rewards. Some travel information remains explicitly marked as development fixtures.
- Legal links point to the currently published draft pages and retain their draft policy version. This package is for testing, not a claim that production launch requirements are complete.

See **FRONTEND_BACKEND_CONTRACTS.md** for the endpoint audit and optional signed-in contract checker. The first build requires internet access; compiled images, database backups and the Windows ngrok profile are not included.

See **FRESH_BACKEND_VALIDATION.md** and the bundled JSON reports for the completed local acceptance checks and their limits.
