# Akita Guard backend

The Python API, firewall worker and connection-attempt observer used by the
Akita Guard iPhone app. The complete implementation, installer, systemd units,
example configuration and isolated Linux smoke checks are in
[caddy-access](caddy-access/README.md). Python uses the standard library only.

## Layout

- `caddy-access/access.py`: authenticated API, lease state and firewall worker.
- `caddy-access/observe.py`: bounded NFLOG connection-attempt metadata observer.
- `caddy-access/install.sh` and `systemd/`: Linux installation and services.
- `caddy-access/*.example.json`: generic examples, never production secrets.
- `tests/`: backend unit and local HTTP API tests.

## Verify

Run from the repository root:

```sh
python3 -B -m unittest discover -s backend/tests -v
bash -n backend/caddy-access/install.sh
```

The network-namespace smoke scripts need Linux root privileges and their documented
iptables/ipset/tcpdump dependencies. They are separate from the portable tests;
do not execute them against production network namespaces.

## Install and upgrade

Follow [the installation and activation procedure](caddy-access/README.md).
From the repository root the installer is `backend/caddy-access/install.sh`.
It requires an external policy with `enabled=false`, preserves existing policy,
leases and token files, and does not start services or activate filtering.

Runtime paths and unit names remain `caddy-access` for compatibility. The source
moved unchanged from `domyshev-labs/homelab-tools` revision
`a03187b0a4df1aeedfceea7109d2a47f574499bb`; source relocation does not change the
running deployment. Actual host addresses, policy and deployment history belong
in the private infrastructure repository.
