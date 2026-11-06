# AnajakMap website

The product site uses dependency-free Node.js templates and static CSS. The repository’s
Flutter client is the app, while the existing legal site supplies the published draft
policy pages. The landing page builds to `dist/` and sends no client-side JavaScript.

## Local development

Use Node.js 24 and run these commands from `website/`:

```sh
npm run dev
npm run lint
npm run typecheck
npm run build
```

The development server builds the site and serves it at `http://127.0.0.1:4173`.
Restart it to rebuild after changes. For setups with Node but no npm, run
`node scripts/serve.mjs`, `node scripts/build.mjs --check`, and
`node scripts/build.mjs` directly. The typecheck script validates rendered
references and template invariants. This site has no TypeScript inputs.

## Vercel preview

Set the project root to `website` if importing the repository into a dedicated
Vercel project. Use the **Other** framework preset, Node.js 24, build command
`node scripts/build.mjs`, and output directory `dist`. Project configuration
is in `vercel.json`. If an existing project serves the legal drafts, use a
dedicated website project to keep that setup separate.

After local checks, sign in to the Vercel CLI, link the dedicated project, and
run `vercel deploy` from this directory to create a preview. Verify the URL
from the deployment result. Leave production promotion and domain setup for a
separate publishing decision.

Optional environment variable names are `PORT` for local preview and
`SITE_URL` for canonical and social URLs on a future production deployment.
`VERCEL_URL` and `VERCEL_ENV` are supplied by Vercel. Preview builds use the
deployment URL for social metadata and include a noindex directive. No secrets
or app API variables are required.

## Content and assets

- The Angkor photo comes from the Flutter asset set. Its source and license
  are recorded in `flutter_app/assets/ATTRIBUTION.md`.
- `icon.png` is a resized copy of the green-and-gold master artwork in
  `flutter_app/assets/branding/anajak_app_icon.png`.
- Companion and map screenshots come from the app’s Android test captures
  `anajak-companion-preview.png` and `anajak-ui-preview.png`.
- The encounter screenshot and original artwork crop come from the app’s
  `journey-capture.png` Android test capture. See `flutter_app/KHMER_CREATURE_ART.md`.
- The itinerary image is the Flutter demo screenshot `test/goldens/itinerary.png`.
  The optimized copies in `assets/` make this website build reproducible.
- The testing CTA opens an inquiry to the support email recorded in the legal
  documents. Add a direct testing or store link once a working public URL is
  available. Published Terms and Privacy pages are linked and labeled as drafts.
