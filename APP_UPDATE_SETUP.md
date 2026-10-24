# Apply this update on the hosting PC

The public backend runs on your other PC. Changes in this checkout do not deploy
there automatically. Keep the existing initialized backend folder and its `.env`.

1. Back up the hosting checkout and database through your existing backup process.
2. Extract the supplied backend source patch **over that checkout**, preserving
   the `AnajakMapBackend/AnajakMapBackend/` path. Alternatively, run the complete
   extracted patch's updater: it can discover one initialized checkout from its
   parent folders or Docker labels and install the listed source files there.
3. Open Docker Desktop. Double-click `Update App Backend.cmd` in the checkout root.
   This builds/restarts only AI, discovery and expense services. It does not
   replace `.env`, Gmail credentials, data volumes or the tunnel.
4. Check registration/email and login, then test weather, AI and maps from the
   updated Android internal-test build. If the tunnel hostname changed, rebuild
   Flutter with the current HTTPS `API_BASE_URL` in your ignored release config.

## If the updater says `.env` is missing

Do not initialize a second backend to repair an update. GitHub and patch downloads
intentionally exclude private `.env`. Extract the patch over the project folder
that already runs your backend, preserving the `AnajakMapBackend/AnajakMapBackend/`
layout and its existing `.env`, then run that project's updater.

The updated launcher prints its expected `.env` path and locates initialized
checkouts from parent folders and Docker Compose labels. If exactly one exists,
it validates every entry in `backend-update-files.txt`, backs up the target's
overwritten source files into `.local/backend-update-backups/`, copies and verifies
the source overlay, then runs the installed updater from the hosting checkout.
It never copies credentials or generates `.env`. If multiple checkouts exist,
specify `-HostingRoot` explicitly instead of choosing one silently. If the original
`.env` has actually been lost, restore it from your backup before updating.

To preview the extracted patch without copying files, starting a build or
restarting services:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AnajakMapBackend\AnajakMapBackend\scripts\update-app-backend.ps1 -CheckOnly
```

If necessary, append `-HostingRoot "C:\anajak_map"` to specify the initialized
project explicitly. Without `-CheckOnly`, the updater applies the source overlay,
builds the three affected services and checks their health. Copy failures stop
before any service restart; the printed backup ZIP retains the original sources.

To find Docker's recorded hosting backend folder manually (PowerShell, paths only):

```powershell
$id = docker ps -aq --filter "label=com.docker.compose.project=anajakmap" --filter "label=com.docker.compose.service=gateway-service" | Select-Object -First 1
if ($id) { (docker inspect --format '{{json .Config.Labels}}' $id | ConvertFrom-Json).'com.docker.compose.project.working_dir' } else { Write-Host 'Open the folder used by your working Start Backend.cmd.' }
```

Inside that backend directory, `Test-Path -LiteralPath .env -PathType Leaf` must
return `True`. There is no need to display or share the file's contents.

For a Git checkout, the simplest update path from the existing project root is:

```powershell
git pull --ff-only origin main
& '.\Update App Backend.cmd'
```

Resolve any Git-reported local source changes before retrying; do not force-reset
the hosting checkout or replace its private settings.

## Optional configuration (backend `.env`, never Flutter)

| Setting | Default | Meaning |
| --- | --- | --- |
| `APP_KHR_PER_USD` | `4000` | Fixed app conversion, not a live exchange quote |
| `WEATHER_PROVIDER` | `open-meteo` in local testing | Destination coordinate weather; review commercial service terms before production |
| `OSRM_URL` | empty | Your compatible routing service base URL; unconfigured routing is unavailable |
| `RPG_ENCOUNTER_TTL_SECONDS` | `900` | Server encounter duration, allowed 60–3600 seconds |
| `GEMINI_VISION_ENABLED` | `false` | Set true only after your selected model is verified for image input and structured output |
| `GEMINI_API_KEY`, `GEMINI_MODEL` | existing configuration | Server-only Google credentials/model; no secrets in mobile config |

Photo recognition uploads only after the user agrees and selects JPEG/PNG up to
4 MiB. The photo passes through the existing private media storage and Google
Gemini. Embedded metadata may be included. Review your published privacy policy
and private-media retention before enabling it. Results are uncertain suggestions,
not verified identification. No photo was sent to Google during automated tests.
Voice AI remains unavailable. Push notifications require a real native push
project and device-token integration; simulated delivery is labelled.

Flutter foreground encounter controls: `--dart-define=RPG_ENCOUNTER_PERCENT=25`
and `--dart-define=RPG_ENCOUNTER_COOLDOWN_SECONDS=300`. Checks occur once a minute
only on the current, resumed adventure screen after opt-in and safety confirmation.
Eligible random rolls consume a cooldown even when no creature appears. Server
proximity, destination review, daily limits and idempotency still apply. No
background location tracking or background notification service is implied.

Offline: the existing Drift database now also stores up to 32 public Wikimedia
thumbnails (512 KiB each) and 40 destination-information responses per backend/account.
Original photo attribution is preserved. Cached information is explicitly stale
on network failure. Map tiles and AI responses are not silently bulk downloaded.
Existing pending edits still require explicit retry and conflict review.

Still required before a production launch: stable HTTPS hosting, real destination
cultural content, reviewed field-game destinations, provider/model verification,
native notification setup, physical-device acceptance, data retention/privacy and
operations review. Android release validation does not validate an iOS release.
