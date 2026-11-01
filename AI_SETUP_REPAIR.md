# Repair Gemini setup on your hosting PC — v2026.10.28.1

If the console still says **“Enter a valid Gemini API key from Google AI Studio.”**, the old script is still running. That exact error is absent from this version. Repeatedly entering a new key into the old script will not install the repair.

## If Google returns HTTP 503

The repaired key-format check has already passed when the console reaches `Checking the configured model with Google...`. HTTP 503 means the request could not be served; it does not confirm whether the credential is valid. Google describes this as temporary overload or service unavailability in its [API errors reference](https://ai.google.dev/gemini-api/docs/api-errors).

Version 2026.10.28.1 retries only HTTP 500/502/503/504, with at most three setup requests and exponential waits of 5 then 10 seconds. It respects a longer `Retry-After` up to 30 seconds. If Google requests a longer wait, it stops and displays that timing. Authentication/permission failures, missing models, HTTP 429 and transport failures are not retried automatically. Google responses and keys are never printed. Settings remain unchanged unless a complete usable answer passes the setup check.

You may run your existing repaired **Update AI.cmd** and explicitly enter `gemini-3.5-flash-lite` at the model prompt instead of accepting `gemini-3.8-flash`. Google documents both model IDs in its [model catalog](https://ai.google.dev/gemini-api/docs/models?hl=en). This is an option, not proof of project quota or current capacity; the setup test must still succeed. The updater retains the model you select and does not silently try other models.

## One-click installation from Downloads

1. Download **AnajakMap-AI-Setup-Repair-v3.zip** onto the computer running Docker/ngrok. Use **Extract All** into a new folder. Do not run files inside the ZIP preview.
2. Open Docker Desktop and wait for the Linux engine, then double-click **Install AI Repair.cmd** in that extracted folder. You do not need to merge nested folders manually.
3. The installer reads only Docker Compose labels to locate the existing initialized hosting project. If it cannot find exactly one project, enter that project's full folder path when asked. Select the root containing `Start Backend.cmd` and `AnajakMapBackend`, or its inner backend folder containing the existing `.env`, `compose.yml` and `pom.xml`.
4. It backs up replaced setup sources, copies only nine named AI setup files, verifies their SHA-256 hashes, and confirms the original `.env` is unchanged. It then displays the exact installed script path and starts **that script**.
5. Before entering your key, confirm that the console shows **AnajakMap AI Setup v2026.10.28.1**, followed by `Script:` and your actual hosting backend path. If that version is absent, stop and use **Install AI Repair.cmd** from the extracted v3 repair folder.

The source installer does not start/stop services, contact Google, or initialize credentials. Once it opens the corrected updater, the updater performs the Google text setup test and AI-service update described below. An initialized hosting folder with its original `.env` is required; the installer refuses to create or replace private configuration.

For an explicit target or a source-only installation, run the extracted installer script with `-HostingRoot "C:\path\to\existing\project" -InstallOnly`. Omit `-InstallOnly` to open the exact installed updater after verification. These paths are examples; no hosting folder is hardcoded.

This repair fixes the local setup error **“Enter a valid Gemini API key from Google AI Studio.”** The old script assumed a particular key format and rejected newer opaque credentials before contacting Google. The repaired script accepts a bounded single-line credential without spaces or control characters; Google decides whether it is valid. It also preserves literal punctuation safely in `.env` and prevents stale shell AI settings from overriding the settings verified during this update.

1. Use **Install AI Repair.cmd** from the extracted v3 ZIP as described above. Keep the existing backend `.env`; this ZIP contains no credentials or database files.
2. Open Docker Desktop and wait for the Linux engine.
3. Double-click **Update AI.cmd**. Paste the complete key into its hidden local prompt. Do not add spaces or quotes around the key, and never paste it into chat. Press Enter without typing to keep an existing saved key.
4. Enter a model ID available to your Google project. The script sends up to three short fictional tests for temporary HTTP 500/502/503/504 failures to Google, then builds and restarts only the AI service. This may consume API quota. Gmail, other services, the database and the public URL are retained.
5. After it finishes, run **Check AI.cmd**. Look for `provider: gemini`, `configured: true`, `demo: false`, and `readinessUp: true`. Then ask a fictional travel question in the signed-in app using its existing backend URL. Readiness and key presence alone do not prove that Google accepted the app's next request.

The updater restores the calling process's original environment after finishing. For later launches, avoid old `AI_PROVIDER`, `GEMINI_MODEL` or `GEMINI_API_KEY` shell overrides that contradict the hosting `.env`; Docker Compose gives shell variables precedence over `.env`.

Photo and voice need separately verified model support and server feature flags. This setup test verifies text only. This targeted repair does not contain the trip Unicode database migration or apply other backend feature updates.

Google describes key creation and server authentication in its [Gemini API key documentation](https://ai.google.dev/gemini-api/docs/api-key?hl=en). Literal credential storage follows Docker's [documented dotenv escaping and precedence rules](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/).
