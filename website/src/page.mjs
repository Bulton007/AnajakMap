const support = 'mailto:forusea168@gmail.com';
const testing = support + '?subject=AnajakMap%20testing%20inquiry';
const legal = 'https://anajakmap-legal.vercel.app';
const arrow = '<span aria-hidden="true">↗</span>';
const next = '<span aria-hidden="true">→</span>';

const features = [
  ['calendar', 'Plan your days', 'Build an itinerary, see it in a trip calendar, and review changes before saving them.'],
  ['compass', 'Discover Cambodia', 'Browse places, read descriptions, see available photos, and bookmark stops for later.'],
  ['map', 'Find your way', 'Open a place directly on the in-app OpenStreetMap view and request directions when routing is available.'],
  ['spark', 'Ask your AI companion', 'Get place suggestions and itinerary ideas. Review what the companion proposes before adding it to your trip.'],
  ['trail', 'Follow Creature Trails', 'Record a journey with GPS and look for fictional creatures at places you’ve visited.'],
  ['people', 'Keep the trip together', 'Track expenses, coordinate with trip members, and download supported trip details for offline reference.'],
];

const paths = {
  calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M7 3v4m10-4v4M3 10h18m-14 5h4"/>',
  compass: '<circle cx="12" cy="12" r="9"/><path d="m16 8-2.5 5.5L8 16l2.5-5.5L16 8Z"/>',
  map: '<path d="m3 6 6-3 6 3 6-3v15l-6 3-6-3-6 3V6Zm6-3v15m6-12v15"/>',
  spark: '<path d="m12 2 2.5 7.5L22 12l-7.5 2.5L12 22l-2.5-7.5L2 12l7.5-2.5L12 2Z"/>',
  trail: '<circle cx="6" cy="6" r="2"/><circle cx="18" cy="18" r="2"/><path d="M6 8v7a3 3 0 0 0 6 0V9a3 3 0 0 1 6 0v7"/>',
  people: '<circle cx="9" cy="8" r="3"/><path d="M3 20v-2a6 6 0 0 1 12 0v2m2-15a3 3 0 0 1 0 6m1 3a5 5 0 0 1 3 4v2"/>',
};

const steps = [
  ['Discover a place', 'Start in Explore and save a stop that catches your eye.'],
  ['Make it part of the trip', 'Add the stop to your itinerary or open it straight on the map.'],
  ['Get your bearings', 'Check directions or ask for AI suggestions when those services are available.'],
  ['Take the scenic route', 'Opt into journey tracking and check for creature encounters at supported stops.'],
];

const stack = [
  ['FL', 'Mobile app', 'Flutter', 'Shared Android and iOS app code for planning trips, exploring places and playing Creature Trails.'],
  ['SB', 'Backend API', 'Spring Boot', 'Java services handle accounts, trips, discovery, AI requests and game progress through a gateway.'],
  ['OSM', 'Map data', 'OpenStreetMap', 'Provides map data for the in-app view. A separate routing service supplies directions when configured.'],
  ['OR', 'Database', 'Oracle', 'Stores accounts, trips and other app records in the documented laptop setup.'],
  ['PG', 'Deployment option', 'PostgreSQL', 'Supported by the repository’s PostgreSQL profiles and database migrations.'],
  ['RD', 'Cache and messaging', 'Redis', 'Supports caching, rate limiting and live chat events across backend instances.'],
  ['MQ', 'Job queue', 'RabbitMQ', 'Carries background jobs and events, including notification delivery.'],
  ['DK', 'Infrastructure', 'Docker', 'Packages the backend services and their dependencies for the documented local setup.'],
];

const screens = [
  ['itinerary.jpg', 390, 844, 'Itinerary', 'A sample trip in the app’s demo mode.', 'Sample Siem Reap itinerary with day tabs and activities'],
  ['map.jpg', 600, 1287, 'In-app map', 'An Android test capture of Phnom Penh with route controls.', 'OpenStreetMap view of Phnom Penh with destination pins and driving directions controls'],
  ['encounter.jpg', 600, 1333, 'Creature encounter', 'An Android test capture after a River Makara encounter.', 'Creature Trails result showing a captured River Makara and game rewards'],
];

const questions = [
  ['Where can I try AnajakMap?', 'The Flutter app targets Android and iOS. Android has been tested. iOS device verification is pending. Contact support for current testing access.'],
  ['What works offline?', 'Previously downloaded trip details can be viewed offline, and supported edits can be queued for sync. Live map tiles, routing, AI and connected features depend on network access.'],
  ['What maps does the app use?', 'The in-app map uses OpenStreetMap. Directions depend on the configured routing service and its coverage. The map image on this site is a captured app screen.'],
  ['Does the AI work everywhere?', 'AI features depend on a configured backend and provider. Availability can vary by feature. You review suggested changes before saving them.'],
  ['How does Creature Trails use location?', 'Journey tracking requires location permission. Tracking runs while the journey screen is open in the foreground. Creature encounters depend on a supported GPS stop and backend checks.'],
  ['Who can help with an account or privacy question?', 'Use the support email below. The linked privacy and terms documents are published review drafts.'],
];

const icon = (name) => '<svg aria-hidden="true" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">' + paths[name] + '</svg>';
const brand = '<a class="brand" href="#top"><img src="/assets/icon.png" width="40" height="40" alt=""><span>AnajakMap</span></a>';
const escape = (value) => value.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

export function renderPage({ origin = '', preview = false } = {}) {
  const title = 'AnajakMap · A travel companion for Cambodia';
  const description = 'Discover Cambodia, plan your days, find your way with OpenStreetMap, and meet fictional creatures along the way.';
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${title}</title>
  <meta name="description" content="${description}">
  <meta name="theme-color" content="#f7f4eb">
  ${preview ? '<meta name="robots" content="noindex, nofollow">' : ''}
  ${origin && !preview ? '<link rel="canonical" href="' + escape(origin) + '/">' : ''}
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="AnajakMap">
  <meta property="og:title" content="${title}">
  <meta property="og:description" content="${description}">
  ${origin ? '<meta property="og:url" content="' + escape(origin) + '/">' : ''}
  <meta property="og:image" content="${escape(origin)}/assets/social.jpg">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:image:alt" content="Stone temple buildings and trees at the Angkor complex in Cambodia">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="icon" type="image/png" href="/assets/icon.png">
  <link rel="apple-touch-icon" href="/assets/icon.png">
  <link rel="stylesheet" href="/styles.css">
</head>
<body id="top">
  <a class="skip" href="#content">Skip to content</a>
  <header class="header wrap">
    ${brand}
    <nav aria-label="Main navigation">
      <a href="#features">Features</a><a href="#screens">App screens</a><a href="#technology">Tech stack</a><a href="#faq">FAQ</a>
    </nav>
    <a class="header-cta" href="#testing">Testing access ${arrow}</a>
  </header>
  <main id="content">
    <section class="hero wrap" aria-labelledby="hero-title">
      <div class="hero-copy">
        <p class="eyebrow"><span></span> A travel companion for Cambodia</p>
        <h1 id="hero-title">Explore Cambodia<br><em>at your own pace.</em></h1>
        <p class="lede">Find places worth a detour, give your trip a plan, and keep a map and an AI travel companion close at hand.</p>
        <div class="actions"><a class="button primary" href="#screens">See the app ${next}</a><a class="button outline" href="#testing">Ask about testing</a></div>
        <p class="hero-note">Available in English and Khmer in the app.</p>
      </div>
      <figure class="hero-visual">
        <img class="hero-photo" src="/assets/angkor.jpg" srcset="/assets/angkor-small.jpg 640w, /assets/angkor.jpg 1200w" sizes="(max-width: 800px) 94vw, 52vw" width="1200" height="801" alt="Weathered stone walls and forest canopy at the Angkor temple complex" fetchpriority="high">
        <div class="device"><img src="/assets/companion.jpg" width="600" height="1339" alt="AnajakMap Companion screen with place recommendations, itinerary planning and travel assistance"></div>
        <figcaption><span>01 / Cambodia</span><strong>Angkor, Siem Reap</strong><small>App shown in testing</small></figcaption>
      </figure>
    </section>
    <section class="section wrap" id="features" aria-labelledby="features-title">
      <div class="section-heading"><p class="eyebrow"><span></span> What’s inside</p><h2 id="features-title">From first idea to last stop.</h2></div>
      <div class="feature-grid">${features.map(([glyph, heading, copy], i) => `<article class="feature"><div class="feature-top"><span class="glyph tone-${i % 3}">${icon(glyph)}</span><span class="index">0${i+1}</span></div><h3>${heading}</h3><p>${copy}</p></article>`).join('')}</div>
    </section>
    <section class="journey" id="how" aria-labelledby="how-title">
      <div class="wrap journey-inner">
        <div><p class="eyebrow"><span></span> How it works</p><h2 id="how-title">One place can start<br><em>a whole trip.</em></h2><p class="section-copy">Begin with somewhere you’d like to see. AnajakMap helps you turn that idea into a day you can follow.</p></div>
        <ol class="steps">${steps.map(([heading, copy], i) => `<li><span class="step-number">0${i+1}</span><div><h3>${heading}</h3><p>${copy}</p></div></li>`).join('')}</ol>
      </div>
    </section>
    <section class="section wrap spotlight" id="cambodia" aria-labelledby="spotlight-title">
      <figure><img src="/assets/angkor.jpg" srcset="/assets/angkor-small.jpg 640w, /assets/angkor.jpg 1200w" sizes="(max-width: 800px) 94vw, 54vw" width="1200" height="801" alt="Stone buildings and shaded paths within Cambodia’s Angkor temple complex" loading="lazy"><figcaption>Angkor temple complex, Siem Reap · <a href="https://www.pexels.com/photo/angkor-wat-temple-complex-in-cambodia-15890461/">Photo via Pexels</a></figcaption></figure>
      <div><p class="eyebrow"><span></span> Cambodia spotlight</p><h2 id="spotlight-title">Start in Siem Reap.</h2><p class="section-copy">Make Angkor the anchor of a sample itinerary, then leave time for a market stop or an afternoon at Ta Prohm.</p><p class="fine">Sample itinerary. Check local access, ticketing and opening hours before visiting.</p><a class="text-link" href="/assets/itinerary.jpg">View the sample itinerary ${arrow}</a></div>
    </section>
    <section class="section gallery-section" id="screens" aria-labelledby="screens-title">
      <div class="wrap">
        <div class="section-heading"><p class="eyebrow"><span></span> Inside the app</p><h2 id="screens-title">See AnajakMap in action.</h2><p class="section-copy">Captured app screens from demo and Android testing.</p></div>
        <div class="gallery">${screens.map(([file, width, height, name, caption, alt], i) => `<figure class="gallery-card"><a class="screen-stage tone-${i}" href="/assets/${file}" aria-label="View full-size ${name.toLowerCase()} screenshot"><img src="/assets/${file}" width="${width}" height="${height}" alt="${alt}" loading="lazy"><span class="expand">${arrow}</span></a><figcaption><h3>${name}</h3><p>${caption}</p></figcaption></figure>`).join('')}</div>
        <p class="fine gallery-credit">Map data © <a href="https://www.openstreetmap.org/copyright">OpenStreetMap contributors</a>.</p>
      </div>
    </section>
    <section class="section wrap creature" aria-labelledby="creature-title">
      <div><p class="eyebrow"><span></span> Creature Trails</p><h2 id="creature-title">A little fantasy<br>along the way.</h2><p class="section-copy">Record a journey, stop somewhere safe, and look for original fantasy creatures inspired by Cambodian settings. Encounters and rewards are part of the game.</p><p class="fine">Requires foreground GPS, an account and a connected backend.</p></div>
      <figure><img src="/assets/creatures.jpg" width="880" height="675" loading="lazy" alt="Original low-poly serpent and River Makara characters in the Creature Trails encounter scene"><figcaption>Original in-game artwork · cropped from an Android test capture</figcaption></figure>
    </section>
    <section class="section wrap technology" id="technology" aria-labelledby="technology-title">
      <div class="section-heading">
        <p class="eyebrow"><span></span> Under the hood</p>
        <h2 id="technology-title">Technology stack.</h2>
        <p class="section-copy">The Flutter app talks to a Spring Boot API. Backend services handle trip data, background jobs and configured travel providers.</p>
      </div>
      <ul class="stack">${stack.map(([mark, role, name, description], i) => `<li><span class="stack-mark tone-${i % 3}" aria-hidden="true">${mark}</span><p class="stack-role">${role}</p><h3>${name}</h3><p class="stack-copy">${description}</p></li>`).join('')}</ul>
      <aside class="stack-note" aria-labelledby="trust-title">
        <h3 id="trust-title">Providers and privacy</h3>
        <p>AI and directions require configured provider services. Journey tracking is opt-in and pauses when you leave its screen or background the app.</p>
        <a class="text-link" href="${legal}/privacy.html">Privacy draft ${arrow}</a>
      </aside>
    </section>
    <section class="section wrap faq" id="faq" aria-labelledby="faq-title">
      <div><p class="eyebrow"><span></span> Good to know</p><h2 id="faq-title">Before you go.</h2></div>
      <div class="questions">${questions.map(([q, a]) => `<details><summary>${q}</summary><p>${a}</p></details>`).join('')}</div>
    </section>
    <section class="testing wrap" id="testing" aria-labelledby="testing-title">
      <div><p class="eyebrow"><span></span> Testing access</p><h2 id="testing-title">Take AnajakMap for a test trip.</h2><p>Ask support about current testing access and include your device platform.</p></div>
      <a class="button gold" href="${testing}">Email about testing ${arrow}</a>
    </section>
  </main>
  <footer class="footer wrap">
    <div>${brand}<p>A Cambodia-focused travel companion.</p></div>
    <nav aria-label="Footer navigation"><a href="${support}">Support</a><a href="${legal}/terms.html">Terms draft</a><a href="${legal}/privacy.html">Privacy draft</a></nav>
  </footer>
</body>
</html>
`;
}
