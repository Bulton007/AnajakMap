# Run AnajakMap Version 2 backend on another Windows PC

Use the same ngrok account as the current server. Version 2 already points to
that account's development hostname, so changing PCs does not itself require a
new Android build. Confirm the hostname in the ngrok dashboard before cutover.

## Choose the correct path

**Already initialized on the other PC:** keep its existing project folder,
private `.env` and Docker volumes. Back it up, apply the source patch using
`APP_UPDATE_SETUP.md`, and run `Update App Backend.cmd`. Then continue at
**Configure ngrok and switch PCs** below. Do not generate new database passwords
or replace that PC's working `.env`.

If its Oracle data already exists but `.env` is missing, use
`RECOVER_BACKEND_CONFIG.md` and **Recover Backend Config.cmd** before attempting
initialization. The tool can recover recorded settings from surviving Docker
containers without resetting the database; recovery stops if required keys are
unavailable or conflicting.

**Fresh PC:** the following steps create a new server and an empty database.
To retain accounts, trips and game progress from the current server, migrate its
database and media volumes together with its matching private configuration
before switching the public endpoint. A source ZIP or `.env` copy alone does
not migrate the data. Leave the current server available until the new one has
been checked locally.

## Install the tools on the fresh PC

A Windows 11 x64 PC with 16 GB RAM is a practical starting point for this full
nine-service/Oracle development stack. This is a sizing recommendation, not an
uptime guarantee. Flutter, Android Studio and a local Java/Maven installation
are not required on the backend-only PC; Docker supplies the Java build tools.

1. Install [Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/)
   with the WSL 2 Linux-container backend. Enable virtualization/WSL if prompted
   and restart Windows if requested. Open Docker Desktop and wait for its engine.
2. Install the ngrok agent in PowerShell:

   ```powershell
   winget install --id Ngrok.Ngrok --exact --source winget
   ```

3. Close and reopen PowerShell, then run:

   ```powershell
   ngrok update
   ngrok version
   docker version
   docker compose version
   ```

The Winget community package can be older than the current agent; the official
updater brings it current. The official Windows installer is also available at
<https://ngrok.com/download/windows>. Windows PowerShell is sufficient for these
launchers; PowerShell 7 (`pwsh`) is not required.

## Copy the current source and initialize a fresh database

Download `AnajakMap-Backend-v2-ngrok.zip` from this task to the other PC's Downloads
folder. The archive contains the current backend source and launchers, not
credentials, database files, node modules or Flutter build tools.

For a new project folder, run:

```powershell
Expand-Archive -LiteralPath "$env:USERPROFILE\Downloads\AnajakMap-Backend-v2-ngrok.zip" -DestinationPath C:\anajak_map
cd C:\anajak_map
Test-Path '.\AnajakMapBackend\AnajakMapBackend\scripts\start-local.ps1'
```

The last command must return `True`. The project root must contain
`Start Public Backend.cmd`; do not add another `AnajakMap-main` nesting level.
Do not extract a fresh setup over an initialized hosting project without using
the existing-project update/backup workflow above.

Start first-time initialization and compilation:

```powershell
cd C:\anajak_map
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AnajakMapBackend\AnajakMapBackend\scripts\start-local.ps1
```

The first run downloads/builds images, generates missing private configuration,
starts Oracle and applies schema migrations. Keep the window open until it
finishes. Do not add `-SkipBuild` on a fresh PC.

Start the local Nginx entrypoint:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AnajakMapBackend\AnajakMapBackend\scripts\start-laptop.ps1
```

Wait until this local URL returns backend JSON:

<http://127.0.0.1:8090/api/v1/auth/config>

## Configure account email and AI on the hosting PC

For a fresh setup, double-click **Configure Email.cmd**. Enter the sender Gmail
address and its 16-letter Google App Password in the hidden local prompt. It
sends one setup email to the sender and checks the registration configuration.
The local overlay supplies the published draft Terms and Privacy links for
testing. A successful SMTP check does not guarantee every recipient's inbox
placement; test registration with a real test address.

If Gemini is required, double-click **Update AI.cmd**. Enter the API key privately
and a model supported by your Google AI Studio project. That helper makes one
short fictional provider test. Photo, voice and RPG practice switches are
separate settings; restore the intended values from your existing configuration
and use `APP_UPDATE_SETUP.md` for their exact meanings. Fresh defaults do not
enable every optional feature automatically.

Do not send `.env`, Gmail App Passwords, Gemini keys or ngrok tokens through
chat/Git. If preserving an existing database, keep its matching credentials and
encryption keys rather than generating replacements.

## Configure ngrok and switch PCs

1. Sign in to the **same** account at
   <https://dashboard.ngrok.com/get-started/your-authtoken>.
2. On the other PC, double-click **Configure Ngrok.cmd** and paste only the token
   value into its hidden prompt. Wait for `Saved locally`.
3. When the new local backend is ready, on the current PC press **Ctrl+C** in
   the existing ngrok window. This ends that public tunnel, not the database.
   Avoid starting two ordinary tunnels for the same hostname simultaneously.
4. On the other PC, double-click **Start Public Backend.cmd**. It checks Docker,
   starts the existing services/Nginx, verifies the API boundary and opens ngrok.
5. Confirm its HTTPS **Forwarding** hostname is
   `reaction-parched-grip.ngrok-free.dev`. Its API base remains
   `https://reaction-parched-grip.ngrok-free.dev/api/v1/`.

If a different hostname appears, check the account before changing Flutter.
Do not use the older `Start Backend.cmd` as the ngrok launcher; that older
entrypoint starts the temporary Cloudflare flow.

## Verify from outside your Wi-Fi

Turn off Wi-Fi on the test phone and use mobile data. Open:

<https://reaction-parched-grip.ngrok-free.dev/api/v1/auth/config>

Expected: JSON with `emailDelivery: true` and `registration: true` after Gmail
setup. The API base URL alone is not a web page and may return 404. If ngrok
shows its browser warning, continue to the site; the JSON API checks are the
relevant test. Then test real login/verification, Explore, Directions and AI in
Version 2. Old accounts will only exist if the database was migrated/restored.

The proxy check also expects unauthenticated `/api/v1/profile` to return 401 and
Actuator/Swagger/internal routes to return 404; those responses are intentional.

## Daily use

- Keep the PC powered, connected to the internet and awake while plugged in.
- Keep Docker Desktop and the ngrok tunnel running. Closing ngrok disconnects
  public access.
- After a Windows restart, open Docker Desktop, wait for its engine and run
  **Start Public Backend.cmd** again. Automatic Windows startup is not configured.
- Keep backups of database/media volumes and their matching private settings.
- Free ngrok currently includes one account-assigned domain, 20,000 HTTP
  requests/month and 1 GB outbound transfer/month; it is bounded testing hosting.
  See [official limits](https://ngrok.com/docs/pricing-limits/free-plan-limits).

This guide does not change or stop the current PC's running server.
