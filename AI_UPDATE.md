# Companion update — 24 October 2026

This update uses the existing AnajakMap app ID and API endpoints. It adds a real
chat composer, visible confirmed turns, suggested questions, answer copying,
duplicate-send prevention, privacy-safe error text and server Retry-After timing.
An unsuccessful request keeps its draft in memory. No automatic retries occur.
The visible conversation is local to this screen session; this update does not
add a conversation browser or restore that screen after the app is closed.

Conversation context is off by default. The English/Khmer switch explains that
enabling it sends up to 12 previous messages from this conversation to Google
Gemini. The backend checks conversation ownership first, extracts assistant text,
limits each previous message to 2,000 Unicode code points, and omits account IDs
and provider metadata. Old clients omit `useContext` and keep latest-question-only
behavior. Turning it off stops including previous messages in future requests;
it does not delete conversations already stored by the backend or sent to Google.
Review the public privacy policy for this processing before a public rollout.

## Hosting PC

Copy the credential-free AI update ZIP contents into the actual repository root
containing `Start Backend.cmd`. Merge folders; do not replace the existing `.env`.
Double-click `Update AI.cmd`. It accepts a hidden Gemini key (or keeps the
existing one), checks the selected model with one fictional Google request,
sets the server-side Gemini configuration, builds the AI service and restarts
only that service. It leaves Gmail, the database and tunnel running. Normal
Google quota/rate limits still apply. No API key belongs in the mobile bundle.

The ZIP contains source updates and scripts, never a `.env`, credential or key.
The updater requires an already initialized repository and Docker Desktop.
If Google rejects the key/model or returns a quota error, no settings are saved.
If a later build fails, the previous container remains running; the validated
settings have been saved for the next startup. The updater does not claim success
until the updated AI service passes its private readiness endpoint.

## Verify before rolling out

Upload signed build 3 to the existing Play internal-testing track. Ask a fictional
travel question; enable context and ask a follow-up; confirm both turns remain
visible. Disable context and confirm future requests contain only the latest
question. Test offline and quota errors without repeated live retries.
Do not use sensitive personal/travel details during acceptance testing.

This update does not implement native voice, image identification, booking,
account deletion or production hosting. Existing unavailable states remain.
The temporary tunnel URL must remain the same as the installed app configuration.
