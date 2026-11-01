# AnajakMap private backend bundle

This ZIP contains the current backend source, Docker Compose/Nginx configuration, repair tools and this PC's existing private configuration in `private-config/.env`. **Keep the ZIP private and out of GitHub or public file shares.**

The private `.env` is separate from the backend folder so extracting an update cannot overwrite the hosting PC's working database passwords, signing keys or Gmail settings. It is a configuration copy, not a database or media backup. No passwords or keys need to be pasted into chat.

## Your existing hosting PC

Your last setup output identified the existing project as:

```text
C:\AnajakMap-Backend-v2-ngrok
```

1. Keep that project's original `AnajakMapBackend\AnajakMapBackend\.env` and its Docker volumes. Back up the project before applying an update.
2. Extract the ZIP's **contents directly into that existing project root**. `Run Backend Local.cmd` must sit beside `Start Backend.cmd` and `AnajakMapBackend`. Avoid adding another `AnajakMap-Backend-v2-ngrok` folder inside it.
3. Double-click **Run Backend Local.cmd**. It retains the existing backend `.env`, checks its recorded database configuration, builds updated sources when needed, applies migrations through the established schema-owner path, starts the services and checks their readiness.
4. If you want to apply the bundle's AI configuration to this existing host, double-click **Use Bundled AI.cmd** after local checks pass. It tests only the bundled Gemini key/model on this hosting PC before updating the three AI settings. The existing database credentials, Gmail settings and other configuration remain in place.
5. Double-click **Run Backend Public.cmd**. It uses the hosting PC's existing ngrok account configuration and opens the public HTTPS endpoint through local Nginx.

The bundled `private-config/.env` is not used to replace an initialized host's `.env`. If the launcher reports a database/configuration mismatch, stop and use the original hosting folder and matching `.env`. If the original file is missing, follow `RECOVER_BACKEND_CONFIG.md` with the surviving original containers. Do not delete volumes or generate new credentials to get past that error.

## A fresh PC with no existing AnajakMap database

1. Install Docker Desktop, enable its Linux-container engine and open it. The launchers use Windows PowerShell; PowerShell 7 (`pwsh`) is not required. A fresh build needs an internet connection to download Maven dependencies, runtime images and the tagged MinIO compatibility sources.
2. Use **Extract All** into one ordinary folder. Open that folder and confirm that `Run Backend Local.cmd` and `AnajakMapBackend` are directly inside it.
3. Double-click **Run Backend Local.cmd**. Only after confirming that no AnajakMap Oracle volume exists may the launcher copy `private-config/.env` into the inner backend folder. It does not generate replacement credentials.
4. Leave the first build/setup running until readiness checks finish. Fresh setup creates an empty database. Existing users, trips, game progress and uploaded media are not transferred by this ZIP.
5. For public access, install the ngrok agent if needed, run **Configure Ngrok.cmd**, enter the account authtoken only in its hidden prompt, then run **Run Backend Public.cmd**. The agent's per-user configuration is not included in this ZIP.

If an Oracle volume already exists on the destination PC, a fresh extraction will not safely adopt this PC's credentials. Use the existing-host path above instead.

## Check the result

Local Nginx exposes:

```text
http://127.0.0.1:8090/api/v1/auth/config
```

Expect backend JSON. The API base URL alone may return 404; use the full path above. Account-specific API endpoints require sign-in. The proxy intentionally blocks external Actuator, Swagger and internal routes.

For the Flutter app, keep the same ngrok account and confirm that its HTTPS forwarding hostname matches the URL already compiled into the app. Moving PCs does not by itself require changing the app URL. Keep the public launcher/ngrok window, Docker, the PC and its internet connection running while testing.

## Email, Gemini and routes

| File | Purpose |
| --- | --- |
| `Configure Email.cmd` | Set or test the sender Gmail account using a hidden Google App Password prompt. |
| `Update AI.cmd` | Test the selected Gemini model with fictional text, then update only the AI service after a usable answer. |
| `Use Bundled AI.cmd` | Read only the Gemini key/model from `private-config/.env`, test them on this host, then apply only the three AI settings if the test succeeds. |
| `Check AI.cmd` | Report non-secret runtime provider/configuration and readiness facts. It does not call Google. |
| `Configure Ngrok.cmd` | Save the hosting PC's ngrok account token locally. |
| `Recover Backend Config.cmd` | Recover recorded configuration when the original `.env` is missing and the original containers remain. |

The bundled Gemini `gemini-3.5-flash-lite` configuration passed one short fictional text request on the PC preparing this bundle. **Use Bundled AI.cmd** verifies it again on the actual hosting PC, with at most three setup requests for temporary server failures, before applying it. It reads only the bundled Gemini key/model; after a successful test it writes only `AI_PROVIDER`, `GEMINI_API_KEY` and `GEMINI_MODEL` to the host's existing `.env`, then updates the AI service. It does not replace that host's complete `.env` or import this PC's database/Gmail credentials.

The existing host otherwise keeps its own saved configuration. Run **Update AI.cmd** if you prefer to enter a different key/model privately. The bundle cannot contain a different key entered only on another PC. A successful text setup test does not guarantee future provider capacity, remaining quota, photo recognition or voice operations.

HTTP 503 means the request could not be served. The updater retries temporary server failures within its stated limits and preserves settings if the test fails. It cannot guarantee Google capacity. Photo/voice require separately verified model support and their server feature flags; a text setup test does not validate them. Manual receipt/booking entry remains available.

OpenStreetMap search, photographs, weather and driving routes also depend on their configured external services. The public OSRM demo is for bounded development testing; it is not a production routing service guarantee. A successful local readiness check does not prove every external provider or every email inbox works.

This is a complete source/configuration transfer bundle, not an offline Docker-image archive or a completed database migration. Use the launcher's actual readiness results and signed-in phone tests before a Play Store rollout.
