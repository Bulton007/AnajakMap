# Integration status — 6 October 2026

Authentication was redesigned from the user's written reference with shared tokens, reusable components, explicit Riverpod auth states and route guards. Gmail SMTP and email-only codes replace exposed development codes. Name/legal consent persistence, public auth configuration, resend, server cooldowns and gateway Retry-After forwarding were added. No Gmail sender or legal URLs are configured yet. See `AUTH_SETUP.md` for current setup and limitations; prior live-test results below are historical.

Current verification includes the full Flutter suite and auth state/contract/layout tests with English/Khmer light/dark golden previews. Android debug compilation succeeds. Six new backend authentication tests pass, and the live Oracle smoke suite passed all 18 workflow groups with the isolated email adapter, including unverified-login rejection, resend Retry-After forwarding and email-only verification/reset. Normal configuration was restored afterward and reports email delivery unavailable, as expected without a sender. The Samsung is not connected for this update; iOS is not built on this Windows host. Social SDK/exchange integration, associated-domain links, Gmail inbox delivery and Figma remain outstanding.

The earlier UI-only milestone is now preserved as explicit demo mode. Default mode uses the backend. Read `../INTEGRATION.md` for the current feature/API matrix.

Completed checks: 26 Flutter unit/widget/contract tests plus the live Flutter repository test, successful connected web build, and a successful Linux Maven multi-module package/test run. Oracle-dependent Java tests are skipped unless configured; live Docker integration is checked separately. Kubernetes manifests render locally and have not been deployed to the remote OpenShift context.

The original demo's visual baselines still pass in English light and Khmer dark. Browser registration, verification, login, trip creation, generation, approval and offline download passed. The full backend smoke suite passed against Oracle. See the root integration report for details.

Samsung SM-S918B / Android 16 debug build and real-device integration test passed through USB to the local backend. UI sign-in, secure-token restoration, travel workflows, uploads, native offline persistence/isolation and logout were verified. The test found and fixed a disposed-session callback. Analyzer and nine connected regression tests pass. Use `run-device.ps1` to launch; add `-Test` to rerun the native suite.

Remaining environment/product requirements include live provider credentials/adapters, a configured map tile provider, push SDK/device-token acquisition, external calendar credentials, Android camera/location permission flows and release checks, iOS build/device checks, and production hosting/HTTPS/backups. Development-provider fixtures must not be represented as real travel facts. Actual Figma authoring and the missing React prototype comparison remain outside this local integration.

