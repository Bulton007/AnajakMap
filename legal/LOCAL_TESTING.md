# Local account testing

The local Docker overlay supplies the published draft URLs and policy version `local-test-draft-2026-10-12` when production values are absent. Flutter identifies this prefix and shows a local-testing notice on registration. Use accounts owned by adult developers and non-sensitive test data. Passwords, verification, sessions and email delivery use the real backend; this is not fake authentication.

These defaults apply only with `compose.local.yml`. Do not deploy that overlay to production. Base compose and Kubernetes still require separately configured approved policies. Environment values override the local defaults. Draft acceptance is stored under the test policy version and must not be represented as acceptance of future production policies.

Start the normal local stack, restart Flutter, open Create account, review the notice and linked drafts, enter your test details, and select consent. Use a new app password (not your Gmail password or SMTP app password). Enter the verification code delivered to your email, then sign in. Do not display or return verification codes through the app API.
