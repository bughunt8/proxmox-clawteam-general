# AGENTS.md

## Project Overview

This repository contains Proxmox helper scripts for deploying an AI agent swarm powered by [ClawTeam](https://github.com/HKUDS/ClawTeam) and [OpenClaw](https://github.com/openclaw/openclaw) inside a Debian LXC container.

## Repository Structure

```
proxmox-clawteam-general/
├── .github/
│   └── workflows/
│       └── ci.yml                    # ShellCheck + BATS CI (GitHub Actions)
├── ct/
│   └── clawteam.sh                   # Run on Proxmox HOST — creates the LXC
├── install/
│   ├── clawteam-install.sh           # Thin orchestrator — sources each module
│   ├── lib/
│   │   └── common.sh                 # Shared helpers (msg_info/ok/warn/error, idempotency)
│   └── modules/
│       ├── 01-system-deps.sh         # apt-get system packages
│       ├── 02-nodejs.sh              # Node.js 22
│       ├── 03-openclaw.sh            # npm install -g openclaw
│       ├── 04-clawteam.sh            # pip venv + clawteam + symlink
│       ├── 05-workspace.sh           # git identity + workspace + spawn-team
│       ├── 06-systemd.sh             # clawteam-board systemd service
│       └── 07-motd.sh                # MOTD helper
├── test/
│   ├── bats/                         # bats-core runner (git submodule)
│   ├── test_helper/
│   │   ├── bats-support/             # output formatting (git submodule)
│   │   ├── bats-assert/              # assertion helpers (git submodule)
│   │   ├── bats-file/                # file/symlink assertions (git submodule)
│   │   ├── stub-functions.bash       # community-scripts FUNCTIONS_FILE_PATH shim
│   │   └── common-setup.bash         # shared setup(), stub helpers, _run_module_script
│   ├── ct/
│   │   └── clawteam.bats             # Tests for ct/clawteam.sh (pct/pveam integration)
│   └── install/
│       └── clawteam-install.bats     # Tests for orchestrator + all 7 modules
└── README.md
```

## Key Files

### `ct/clawteam.sh` — Proxmox host script

Supports two execution modes:

**Standalone mode** (no internet dependency for framework):
```bash
STANDALONE=1 bash ct/clawteam.sh

# Override defaults:
CT_ID=110 CT_RAM=8192 CT_DISK=20 STANDALONE=1 bash ct/clawteam.sh

# Update an existing container:
bash ct/clawteam.sh --update <vmid>
```

**community-scripts mode** (interactive wizard via build.func):
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bughunt8/proxmox-clawteam-general/main/ct/clawteam.sh)"
```

**Proxmox VE CLI commands used** (`pct` / `pveam`):
- `pveam update` — refresh template catalog
- `pveam available` — find latest Debian 13 template
- `pveam download` — download template to local storage
- `pvesh get /cluster/nextid` — get next available container ID
- `pct create` — create LXC with all resource/network flags
- `pct exec` — run install script inside container
- `pct push` — copy install script into container
- `pct start` — ensure container is running (update path)
- `pct status` — check container state

### `install/clawteam-install.sh` — thin orchestrator

Sources each module in `install/modules/` in order. Compatible with:
- community-scripts injection (FUNCTIONS_FILE_PATH set)
- Standalone direct execution as root

### `install/modules/` — individually runnable modules

Each module:
- Sources `install/lib/common.sh` for shared helpers
- Is idempotent (marker files in `/var/lib/clawteam/done/`)
- Can be run standalone: `bash install/modules/04-clawteam.sh`
- Fails fast with a non-zero exit on error

| Module | Purpose |
|---|---|
| `01-system-deps.sh` | apt-get: curl, git, tmux, python3-venv, libzmq3-dev |
| `02-nodejs.sh` | Node.js 22 via setup_nodejs or NodeSource |
| `03-openclaw.sh` | `npm install -g openclaw@latest` |
| `04-clawteam.sh` | Python venv at `/opt/clawteam/.venv`, pip install clawteam[p2p], symlink |
| `05-workspace.sh` | git identity, workspace init, `clawteam team spawn-team openclaw-team` |
| `06-systemd.sh` | `/etc/systemd/system/clawteam-board.service`, `systemctl enable` |
| `07-motd.sh` | `/etc/update-motd.d/99-clawteam` |

## Conventions

- Follow the [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) pattern for the host script
- Use `var_*` defaults for LXC settings (4 CPUs, 4 GB RAM, 10 GB disk, unprivileged)
- Call `variables` before `header_info` so `APP`/`NSAPP` are resolved first
- Use `apt-get` (not `apt`) for non-interactive package installation
- Use `npm install -g` (not `npm update`) for idempotent OpenClaw upgrades
- Use absolute paths throughout — avoid bare `cd` calls
- Use `-d` / `-n` short flags for `clawteam team spawn-team` (not `--agent-name`)
- Configure a git identity before running `clawteam team spawn-team`
- Debian 13 (Trixie) as the base OS
- Symlink `clawteam` to `/usr/local/bin` after installation
- All modules are idempotent — safe to re-run

## Dependencies

- **ClawTeam**: `pip install clawteam` — PyPI package, Python ≥ 3.10
- **ClawTeam P2P**: `pip install clawteam[p2p]` — optional ZeroMQ transport (requires `libzmq3-dev`)
- **OpenClaw**: `npm install -g openclaw` — Node.js package
- **Node.js**: Version 22
- **System packages**: git, tmux, python3, python3-venv, build-essential, libzmq3-dev
- **Proxmox VE tools**: `pct`, `pveam`, `pvesh` (available on any PVE host)

## Testing

Tests use [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System).
External commands are stubbed via PATH-shadowing so no real packages are installed during testing.

### First-time setup

Initialise submodules after cloning:

```bash
git submodule update --init --recursive
```

### Run all unit tests (no root required)

```bash
./test/bats/bin/bats test/ct/clawteam.bats
./test/bats/bin/bats test/install/clawteam-install.bats
```

### Run a single module test

```bash
# e.g. just the systemd module tests
./test/bats/bin/bats --filter "module 06" test/install/clawteam-install.bats
```

### Run integration tests (requires root inside a container)

```bash
# Inside a Debian 13 container or GitHub Actions
./test/bats/bin/bats test/install/clawteam-install.bats
```

### Run a single module standalone (requires root inside an LXC)

```bash
bash install/modules/04-clawteam.sh
```

### Run with verbose output

```bash
./test/bats/bin/bats --verbose-run test/ct/clawteam.bats
```

### ShellCheck (static analysis)

```bash
shellcheck --exclude=SC1090,SC2034 ct/clawteam.sh
shellcheck --exclude=SC1090,SC1091,SC2154 install/clawteam-install.sh
shellcheck --exclude=SC1090,SC1091,SC2154 install/modules/*.sh
shellcheck install/lib/common.sh
```

### CI

GitHub Actions runs ShellCheck and all BATS tests on every push and pull request.
Integration tests execute inside a `debian:trixie` container as root.
See `.github/workflows/ci.yml`.
