# Recover missing backend configuration without replacing the database

Run this on the PC that reports an existing Oracle volume but has no `.env`.

1. Open Docker Desktop and wait for its Linux engine.
2. Extract `AnajakMap-Recover-Config.zip` into the same project root that contains
   `Start Backend.cmd`, replacing only the supplied recovery tool files.
3. Double-click **Recover Backend Config.cmd**.
4. If it reports successful recovery, run **Start Public Backend.cmd**. That
   verifies actual backend startup using the recovered settings.

The tool reads recorded container environment settings for the `anajakmap`
Compose project, including stopped containers. It requires the original Oracle
container to be attached to `anajakmap_oracle-data`, refuses conflicting or
missing required settings, and refuses to overwrite an existing `.env`.
It saves values locally without printing them. It does not generate passwords,
reset users, modify database schemas, delete volumes or restart containers.

If containers were deleted, the data volume alone does not contain all of the
application signing/encryption settings this recovery needs. An incomplete
recovery stops without creating `.env`; restore the matching private backup or
report the recovery message, never secret values. Existing database credentials
could also have been changed independently after container creation, so service
startup remains the final check of the recorded settings.

A read-only preflight is available from the project root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AnajakMapBackend\AnajakMapBackend\scripts\recover-env.ps1 -CheckOnly
```

The source backend ZIP intentionally contains no private `.env`. Do not rename
`.env.example` to repair an existing database: its placeholders do not match
that database. Keep the recovered file private and out of Git/chat.
