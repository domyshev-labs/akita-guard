# Akita Guard

Akita Guard manages temporary public-IP access to home services. This repository
contains the native iPhone client and its Linux backend, with no third-party
Swift or Python packages required.

## Repository layout

| Path | Purpose |
| --- | --- |
| `App/`, `Core/`, `Assets.xcassets/` | SwiftUI iPhone app, shared API client and assets |
| `AkitaGuard.xcodeproj`, `Info.plist` | iOS project and application configuration |
| `Package.swift`, `Tests/` | Portable Swift API-contract tests |
| `backend/caddy-access/` | Python API, firewall worker, observer and Linux installer |
| `backend/tests/` | Backend unit and local HTTP tests |
| `Brand/`, `ICON.md` | Icon artwork and generation provenance |
| `VALIDATION.md` | Historical validation and migration checks |

The backend moved from `domyshev-labs/homelab-tools/caddy-access` on 2026-10-18.
Runtime paths and service names remain unchanged. Actual host configuration,
network addresses, policies and deployment audit logs belong in the private
infrastructure repository. Never commit tokens or filled environment files.

## iPhone setup

The app requires iOS 17 or later, targets iPhone in portrait orientation and
supports system light/dark appearance, including iPhone 15 Pro Max layouts.

1. Open `AkitaGuard.xcodeproj` in Xcode and select **AkitaGuard**.
2. Choose your Team / Personal Team in Signing & Capabilities. If needed, replace
   `com.domyshev.AkitaGuard` with your own unique bundle identifier.
3. Connect your iPhone, confirm trust and enable Developer Mode if requested.
4. Select the iPhone as the run destination and press Run.

Physical-device installation and signed IPA distribution require the owner's
Apple signing account. No Apple account is included in the repository.

## Backend setup

Follow [backend installation and activation](backend/caddy-access/README.md).
The API authenticates requests; a separate root worker reconciles expiring leases
with iptables/ipset. The optional observer reports bounded connection-attempt
metadata. Installation does not activate filtering automatically.

From the repository root:

```sh
sudo bash backend/caddy-access/install.sh /path/to/root-policy.json
```

Read the complete backend procedure before running this command: dependencies,
private management routing, an initially disabled policy and a tested rollback
are required. Keep the management API private and retain authentication on the
services protected by the IP allowlist.

## Connect the app

1. Make the API reachable, for example through Tailscale and a subnet router.
2. Open Settings and enter your server URL, e.g. `http://192.168.1.10:9120`.
   No production server address is preconfigured.
3. Privately obtain the value of `CADDY_ACCESS_TOKEN` from the server's
   `/etc/caddy-access/api.env` using your administrator terminal and enter it in
   the app. Never paste it into source, documentation, logs or a URL.
4. Select Save and verify, and allow local-network access in iOS.
5. On Access, select + and enter the work computer's public IP, an optional label
   and a lifetime: 1, 4, 8, 24 hours, 7 days or 30 days. The app waits for the
   backend to confirm application.
6. Swipe or long-press an entry to revoke it, then confirm deletion.

The current app interface is in Russian; documentation is in English.
Supported endpoints are GET/POST `/v1/entries`, GET `/v1/status`, PATCH/DELETE
`/v1/entries/ID` and GET `/v1/attempts`. The app does not change server policy,
permanent home-network access or Tailscale configuration.

A 202 response means queued, not applied. Success requires fresh `state=applied`
with the matching revision. Disabled filtering, stale status, errors and changes
from another device are handled separately. A POST is not retried automatically
when the connection is lost; refresh the list first.

## Credentials and networking

- The token lives only in Keychain with `WhenUnlockedThisDeviceOnly`, never in
  UserDefaults, iCloud or logs. Delete token clears the phone's copy without
  deleting server leases. Only the server URL is stored in UserDefaults.
- Ephemeral URLSession disables cookies and disk cache. Redirects are rejected
  so the token cannot be forwarded to another destination.
- HTTP is permitted only for numeric private IPv4, loopback and Tailscale
  addresses. HTTPS may be configured separately. ATS local-network opt-in is
  enabled. The app does not detect the phone's public IP or read the clipboard
  automatically.
- With a Tailscale subnet router, encryption ends at that router; HTTP continues
  over the LAN to the API. Configure server HTTPS for TLS across that final hop.

## Demo

Select **AkitaGuard Demo** and an iPhone Simulator. Demo addresses are fictional,
operations are in memory, Keychain is not read and no server requests are made.
The UI visibly marks demo mode. The primary scheme does not enable it.

## Verification

```sh
swift test
python3 -B -m unittest discover -s backend/tests -v
bash -n backend/caddy-access/install.sh
```

The app compiles the same `Core/*.swift` directly without downloading packages.
Swift tests cover API contracts, Bearer authentication, Python ISO timestamps,
invalid-token handling, disabled/stale status, concurrent revisions, 202/polling,
invalid responses and URL/IP validation. Tests use fictional tokens.
Linux firewall/NFLOG smoke checks are documented separately in the backend.

If Command Line Tools is the selected developer directory, use
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for builds without
changing global `xcode-select` settings.

## Debug provisioning from a trusted Mac

Debug builds support initial setup with `AKITA_SETUP_SERVER` and
`AKITA_SETUP_TOKEN` in the child process environment used to launch devicectl.
Do not put values in command arguments, logs or project files. The app saves the
token in Keychain and clears these environment variables. The local receipt
`Library/Caches/developer-setup-result.json` contains only `configured` and
`connected`. This feature is not compiled into Release builds.

## Version 1.1 behavior

- Labels start empty and can be renamed without changing expiry.
- Seven- and thirty-day leases require the updated API and a 2592000-second
  server limit. Renew starts a new lifetime and clears manual blocking.
- Expired entries remain available for up to 30 days within the server's bounded
  history. Block revokes access while preserving the entry and expiry; unblock
  restores only the remaining lifetime. Expired entries must be renewed.
- Delete removes the entry and revokes access after confirmation.
- Refresh controls check connectivity immediately. While active, the app checks
  roughly every 15 seconds and shows the last successful connection time.
- Attempts shows blocked Caddy connection sources, last observation and approximate
  counts. Manual refresh and pull-to-refresh show the load time; an independent
  server heartbeat identifies stale data. The visible tab updates with the active
  app's periodic checks. Allowing an observed IP requires a form and confirmation.
- The phone and work computer may use different networks. Observed sources belong
  to connections reaching Akita, including scanners; IP ownership is not established.
  Data is rate-limited, retained for at most a day and is not a complete audit log.
  Observations never grant access automatically.

## Artwork

The icon was generated with imagegen. Original artwork and the final prompt are
preserved in [ICON.md](ICON.md) and `Brand/`.
