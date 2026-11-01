# Backend startup path repair — 29 October 2026

This repair fixes the `Substring` / `startIndex cannot be larger than length of string` error in **Run Backend Local.cmd**. Source fingerprinting now resolves the filesystem path before calculating relative filenames and checks that every source stays inside the selected backend directory.

## Apply to the existing hosting folder

1. Close the failed launcher window.
2. Extract the contents of **AnajakMap-Startup-Path-Repair.zip** directly into your existing project root, for example `C:\AnajakMap-Backend-v2-ngrok`. Allow replacement of the two included PowerShell source files. The archive contains no `.env` or other credentials.
3. Confirm the updated file is at `C:\AnajakMap-Backend-v2-ngrok\AnajakMapBackend\AnajakMapBackend\scripts\ready-backend.ps1`.
4. Open Docker Desktop and run **Run Backend Local.cmd** from that same project root. Leave the build/migrations running until the service readiness and Nginx checks finish.
5. Run **Use Bundled AI.cmd** if you want to apply the private bundle's tested Gemini key/model to this host. It verifies the settings before applying only AI configuration.
6. Keep **Run Backend Public.cmd** / ngrok running on the account that owns the app's configured hostname.

The complete **AnajakMap-Backend-Ready-PRIVATE-v2.zip** also includes this repair and current backend sources. On an existing host, extract its contents into the original hosting project, preserving its inner backend `.env` and Docker data. Keep this complete private bundle out of GitHub and public file shares.

## Validation and limits

113 synthetic Windows PowerShell 5.1 checks passed, including the original path-normalization failure, relative and nested extraction paths, source-change detection, child-process argument handling, credential guards, environment restoration and junction handling. A real source fingerprint also succeeded on the development checkout through a normalized `scripts\..` path. These checks did not start Docker or change a real database.

The Samsung test against the configured public backend restored its session, loaded an Explore photograph, acquired foreground GPS and accepted a map destination pin. A fictional companion question succeeded after an earlier failure. The hosted route endpoint returned legacy demo cost/time fields instead of road geometry; rebuilding the updated discovery service on the hosting PC is still required. A successful `/api/v1/auth/config` response alone does not verify routes, Gemini reliability or actual email delivery.
