# proxmox-clawteam-general

> **OpenClaw ClawTeam on Proxmox LXC** — Deploy an AI agent swarm powered by
> [ClawTeam](https://github.com/HKUDS/ClawTeam) and
> [OpenClaw](https://github.com/openclaw/openclaw) inside a single Debian LXC
> container, launched directly from the Proxmox console using the
> [community-scripts](https://community-scripts.org/scripts) helper framework.

---

## Overview

[ClawTeam](https://github.com/HKUDS/ClawTeam) turns a single CLI agent into a
*swarm* — it lets AI agents spawn sub-agents, assign tasks with dependency
chains, communicate through inboxes, and co-ordinate work in parallel git
worktrees, all over a shared tmux session or a built-in Web UI.

[OpenClaw](https://github.com/openclaw/openclaw) is a personal AI assistant
(Node.js) that connects to 20+ messaging channels and can act as a worker agent
inside a ClawTeam swarm.

This repo provides the **Proxmox helper scripts** (modelled on the
[community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE)
convention) that:

1. Create a Debian 13 LXC container on your Proxmox host.
2. Install Python 3, Node.js 22, tmux, `clawteam`, and `openclaw` inside it.
3. Bootstrap a default team called **`openclaw-team`** and wire up a systemd
   service for the ClawTeam Web dashboard.

---

## Repository structure

```
proxmox-clawteam-general/
├── ct/
│   └── clawteam.sh          # Run on the Proxmox HOST — creates the LXC
├── install/
│   └── clawteam-install.sh  # Run inside the LXC — installs everything
└── README.md
```

---

## Quick start

### Prerequisites

* Proxmox VE 8.x / 9.x with internet access.
* A Proxmox **Shell** (not the LXC console — the PVE host shell).

### One-command install

Open the **Proxmox Shell** and run:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bughunt8/proxmox-clawteam-general/main/ct/clawteam.sh)"
```

The script will interactively ask for container settings (or accept the
defaults shown below) and then provision the LXC.

### Default container settings

| Setting      | Default     |
|--------------|-------------|
| OS           | Debian 13   |
| CPUs         | 4           |
| RAM          | 4096 MB     |
| Disk         | 10 GB       |
| Unprivileged | yes         |

---

## Inside the LXC

Once the container is running, open its console (`pct enter <vmid>`) or SSH
into it.

### Create a new team

```bash
cd /root/workspace/openclaw-workspace

# Spawn a new team with you (or an agent) as the leader
clawteam team spawn-team my-team -d "My OpenClaw swarm" -n leader
```

### Spawn OpenClaw worker agents

```bash
# Each worker gets its own git worktree + tmux window
clawteam spawn tmux openclaw --team my-team --agent-name alice \
  --task "Summarise the latest tech news"

clawteam spawn tmux openclaw --team my-team --agent-name bob \
  --task "Write a Python script to parse the summary"
```

### Watch the swarm

```bash
# Tiled tmux overview
clawteam board attach my-team

# Web dashboard (served on port 8080)
clawteam board serve --port 8080
# Then open http://<LXC-IP>:8080 in your browser
```

The **`clawteam-board`** systemd service starts the Web dashboard automatically
on port **8080** at container boot.

### Update ClawTeam / OpenClaw

Re-run the Proxmox host script — it detects an existing installation and
upgrades both `clawteam` (pip) and `openclaw` (npm):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bughunt8/proxmox-clawteam-general/main/ct/clawteam.sh)"
```

---

## How the scripts work

### `ct/clawteam.sh`  _(Proxmox host)_

Follows the standard
[community-scripts](https://github.com/community-scripts/ProxmoxVE) pattern:

```
source build.func   →  header_info / variables / color / catch_errors
                    →  start / build_container / description
```

`build_container` uses the `var_*` defaults to create the LXC and then calls
`install/clawteam-install.sh` inside it via `$FUNCTIONS_FILE_PATH`.

The `update_script()` function is invoked when the script is re-run against an
existing container — it upgrades ClawTeam and OpenClaw in place.

### `install/clawteam-install.sh`  _(inside the LXC)_

1. Updates the OS and installs system packages
   (`git`, `tmux`, `python3`, `python3-venv`, `libzmq3-dev`, …).
2. Installs Node.js 22 via the community-scripts `setup_nodejs` helper.
3. Installs **OpenClaw** globally via `npm install -g openclaw@latest`.
4. Creates a Python virtualenv at `/opt/clawteam/.venv` and installs
   **ClawTeam** (including the optional ZeroMQ P2P transport).
5. Symlinks `clawteam` into `/usr/local/bin`.
6. Bootstraps a default git workspace at `/root/workspace/openclaw-workspace`
   and creates the initial **`openclaw-team`** team.
7. Installs a **systemd service** (`clawteam-board`) for the Web dashboard.
8. Writes an MOTD helper with usage reminders.

---

## References

* [ClawTeam — HKUDS](https://github.com/HKUDS/ClawTeam)
* [OpenClaw](https://github.com/openclaw/openclaw)
* [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE)
* [community-scripts.org](https://community-scripts.org/scripts)

---

## License

MIT
