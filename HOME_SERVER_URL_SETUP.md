# Use your own PC as the Anajak backend server

The Spring Boot API already exists. A public hostname directs internet clients
to its gateway; it does not create a new API or move the database elsewhere.

Recommended traffic path:

    Flutter -> public HTTPS hostname -> tunnel -> Nginx -> Spring gateway
                                                     -> private services/database

In the current laptop setup, Nginx is on host port **8090**. The development
gateway is also available locally on 8080; publish the Nginx entrypoint rather
than the development gateway. Keep Oracle, Redis, RabbitMQ and object storage
private. Inspect the existing compose port bindings before hosting on a new PC.

## Option A: own domain + Cloudflare named tunnel

This is the recommended stable address, for example
`https://api.YOUR_ACTUAL_DOMAIN/api/v1/`. The example is not a registered domain.
Domain registration is usually paid separately; this does not require a VPS.

1. Register a domain with a registrar and add its DNS zone to Cloudflare.
2. In Cloudflare Zero Trust, create a remotely managed **Cloudflared** tunnel.
3. Install its connector on the actual hosting PC using Cloudflare's generated
   Windows service instructions. Enter the tunnel token only on that PC; never
   put it in Git, Flutter, screenshots or chat. If running the connector in a
   container, `localhost` is that container, not the Windows host; use a verified
   Docker-network service address instead.
4. Add a published application route for hostname `api.YOUR_ACTUAL_DOMAIN` with
   HTTP origin `http://localhost:8090` when the connector runs directly on Windows.
   Cloudflare handles the public HTTPS connection. Do not expose administrative
   Actuator/Swagger routes through another public gateway port.
5. Verify public auth configuration and real account flows from a phone on
   mobile data. A Cloudflare Access browser-login gate in front of the mobile
   API would require a separate compatible authorization design; retain the
   existing application authentication.
6. Configure authentication email/public callback URLs consistently with the
   stable hostname. Preserve existing database credentials and volumes.
7. Update Flutter's ignored `config/production.local.json`:

       "API_BASE_URL": "https://api.YOUR_ACTUAL_DOMAIN/api/v1/"

8. Build and verify a signed release with the existing package/upload key.
   The client contains this public URL, never backend credentials.

A named tunnel retains its configured hostname after restarts while the domain,
DNS and tunnel configuration remain in place. It does not need your home IP to
be static or inbound router port forwarding.

## Option B: free account-assigned ngrok development domain

If you do not own a domain, create an ngrok account. Its free plan assigns one
development hostname to that account; copy the actual hostname from its dashboard.
On this checkout, install the official agent once, then use these launchers:

1. Double-click **Configure Ngrok.cmd**. Sign in to
   <https://dashboard.ngrok.com/get-started/your-authtoken>, copy your authtoken,
   and paste only its value into the hidden local prompt. The official agent
   stores it in your user profile outside the repository. Never share it in chat.
2. Double-click **Start Public Backend.cmd**. This starts Docker if necessary,
   starts the existing backend without replacing credentials, verifies the
   Nginx API and blocked internal paths, then opens ngrok. It does not start
   another random Cloudflare tunnel. If the matching ngrok agent already runs,
   it reuses that endpoint without starting a duplicate. Keep the original tunnel
   window open.
3. Copy the actual HTTPS **Forwarding** URL and append `/api/v1/`. This public URL
   can be shared to configure Flutter; the authtoken must remain private.

For a manual equivalent after Docker/Nginx are ready:

    ngrok http http://127.0.0.1:8090 --inspect=false

Use the actual HTTPS address printed by the agent plus `/api/v1/` in Flutter.
This is suitable for bounded testing, not an unlimited hosting plan. As checked
25 October 2026, free quotas include 1 GB outbound transfer and 20,000 HTTP
requests per month. The endpoint has no automatic timeout, but stops being
usable when the agent/PC/backend is offline or quota is exhausted. Follow its
background-service instructions for unattended operation. The launcher disables
the agent's local request-payload inspector for authentication traffic.
Configuring unattended Windows startup is a separate step; these foreground
launchers alone do not guarantee restart after a power outage or reboot.

## Option C: dynamic DNS and direct inbound HTTPS

DuckDNS offers a free dynamic DNS name. This additionally needs reachable public
internet addressing, router forwarding and a correctly maintained HTTPS reverse
proxy. Dynamic DNS does not bypass ISP CGNAT or blocked inbound ports. Use the
tunnel choices above if you cannot provide a reachable public IP.

## Keeping the PC available

- Start the existing initialized backend with `Start Backend.cmd`; do not
  initialize a new database or replace its `.env` when changing the public URL.
- Configure the hosting PC to remain awake while plugged in and arrange Docker,
  backend and tunnel startup after reboot. Confirm behavior after a real reboot;
  Docker Desktop startup can depend on a Windows user sign-in.
- Keep persistent database/media volumes, backups and security updates. A stable
  URL is not a backup or a guarantee against power/ISP/PC outages.
- Verify the public API from outside Wi-Fi before distributing an app build.
- Nginx is the reverse proxy; Docker runs the services. Kubernetes is optional
  and unnecessary for this single-PC setup.

## Official references checked 25 October 2026

- [Cloudflare: create a named tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel/)
- [Cloudflare: temporary Quick Tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/)
- [ngrok: free domain and limits](https://ngrok.com/docs/pricing-limits/free-plan-limits)
- [ngrok: domains](https://ngrok.com/docs/gateway/domains)
- [DuckDNS](https://www.duckdns.org/)
