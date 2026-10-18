# Project validation

Historical results below describe checks at the stated dates, not checks rerun
by a documentation edit.

## Initial app validation, 2026-10-17

- Xcode 27.1 (27A9275), iOS SDK 27.1; minimum iOS 17, iPhone only.
- Debug generic iOS Simulator build: BUILD SUCCEEDED.
- Debug generic iOS device build with CODE_SIGNING_ALLOWED=NO: BUILD SUCCEEDED.
- Swift Package: 11 tests, zero failures.
- Demo launched in a separate iPhone 15 Pro Max Simulator running iOS 26.5.
- Main screen, add form, settings and light/dark appearance inspected in screenshots
  containing only fictional IPs.
- No server token was read or included. Production server configuration and leases
  were unchanged during initial app creation.
- Initial Apple signing, physical-device installation and authenticated end-to-end
  requests were left to the setup procedure in README.md.
- No downloaded dependencies. Build caches and DerivedData remain outside the project.
- No analytics, background VPN service or phone public-IP detection. The app manages
  the installed API over the existing Tailscale route.

Project, schemes, modules and bundle identifier were renamed to AkitaGuard. Simulator
and unsigned device builds and all 11 tests passed again. The opaque RGB 1024×1024
AppIcon and app name were checked on the Simulator home screen. Artwork provenance
is in `Brand/` and `ICON.md`.

## Public repository preparation

The preconfigured home server URL was removed. Documentation/tests use examples;
users enter their own server in Settings. Local screenshots, user Xcode settings
and build outputs are excluded from Git.

## Version 1.1, 2026-10-18

- Fifteen Swift tests passed: 30-day TTL, empty labels, history query, compatible
  blocked decoding, PATCH rename/block without TTL, and attempts freshness.
- Signed iPhone and iOS Simulator builds passed.
- Lease/action lists, Attempts load times and the initially empty add-form label
  were inspected on iPhone 15 Pro Max Simulator.
- Version 1.1 (build 2) was installed and launched on the connected iPhone.
  Real-token requests were not included in test logs or Git.
- Seventy-eight backend unit/HTTP tests, an isolated Linux NFLOG smoke check and
  the live 30-day → rename → block → unblock → delete cycle passed.
  Actual addresses and deployment audit remain in the private infra repository.

## Backend repository migration, 2026-10-18

The backend implementation, installer, units, examples, smoke scripts and two test
modules moved unchanged from homelab-tools revision
`a03187b0a4df1aeedfceea7109d2a47f574499bb` to `backend/`. Existing iOS source paths,
Xcode project references and runtime service/state paths were preserved. This
source migration did not redeploy production or rerun privileged Linux smoke tests.

Migration checks passed: 20 Python backend unit/HTTP tests, 15 Swift tests using
Xcode's developer directory, installer Bash syntax, and 58 remaining homelab-tools
tests. Command Line Tools alone failed on SDK/compiler mismatch; selecting Xcode
for this command resolved it. Local HTTP tests required permission to bind loopback.
Privileged Linux smoke checks were not rerun for an unchanged implementation.
