# VLESS + Reality VPN Server Setup for Ubuntu VPS (Xray)

This repository provides a simple script to deploy a VLESS server with REALITY transport on an Ubuntu VPS using Xray core.  

Installation and client management are performed entirely from the terminal in a single interactive script. No Docker containers, no web interfaces, no additional services are required.

## Requirements

- **OS:** Ubuntu (tested on 24.04). May work on other Debian-based systems.
- **Root:** The manager must be run as root (or with `sudo`).
- **Port:** Configurable at install (default 443); the chosen port must be free (no other service should listen on it).

## Running the manager

From the repo root:

```bash
git clone https://github.com/ivan-khludov/vless-reality-setup.git
sudo ./vless-reality-setup/bin/vless-manager.sh
```

You’ll see the main menu:

```
===============================
  VLESS Reality Server Manager
===============================

1) Install
2) Add client
3) Remove client
4) Show clients
5) Change port
6) Change SNI
7) Uninstall server
0) Exit

Select option:
```

- **1) Install** — First-time setup: installs dependencies and Xray, generates keys, creates VLESS Reality config, starts the service, and prints the first client link. You’ll be prompted for SNI (default `www.cloudflare.com`), listen port (default 443), and client name.
- **2) Add client** — Adds a new client (new UUID and short id), restarts Xray, and appends the new link to the clients file. Requires an existing install.
- **3) Remove client** — Shows the client list, then asks for the client number to remove. You must type **YES** to confirm. Restarts Xray and rewrites the clients file.
- **4) Show clients** — Lists all clients with their numbers, UUIDs, shortIds, and VLESS links.
- **5) Change port** — Prompts for the new listen port, updates config, restarts Xray, and rewrites client links.
- **6) Change SNI** — Prompts for the new SNI (and updates Reality dest), restarts Xray, and rewrites client links.
- **7) Uninstall server** — Stops and disables Xray, removes the binary, config directory, and systemd unit. You must type **DELETE** to confirm. The `files/` directory (keys and client links) is left intact.
- **0) Exit** — Quit the manager.

Dangerous actions (**Remove client** and **Uninstall server**) require explicit confirmation as noted above.

## Backup

Before every config change (add/remove client, change port or SNI), a backup of the current Xray config is created in `files/backups/` with a timestamped name:

- **Path:** `files/backups/config.json.bak.<unix_timestamp>`

You can restore by copying a backup over `config.json` and restarting Xray if needed.

## Important paths

| Path                                        | Description                                                                                                   |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `/usr/local/etc/xray/config.json`           | Xray config                                                                                                   |
| `files/backups/config.json.bak.<timestamp>` | Timestamped config backups (created before each config change)                                                |
| `files/vless-reality-clients.txt`           | Client VLESS links (`files/` is gitignored)                                                                   |
| `files/.vless-reality-public-key`           | Server Reality public key; used when adding clients                                                           |
| `files/server-ip`                           | Cached server IP for links; set at first run. Edit and re-run “Change port” or “Change SNI” to refresh links. |

## Service

- **Start:** `sudo systemctl start xray`
- **Stop:** `sudo systemctl stop xray`
- **Status:** `sudo systemctl status xray`
- **Logs:** `journalctl -u xray -f`

Use the links from `files/vless-reality-clients.txt` in a VLESS Reality–compatible client (e.g. v2rayN, Nekoray, Shadowrocket, Hiddify).
