# AGENTS.md

## Project Overview

This repository contains Proxmox helper scripts for deploying an AI agent swarm powered by [ClawTeam](https://github.com/HKUDS/ClawTeam) and [OpenClaw](https://github.com/openclaw/openclaw) inside a Debian LXC container.

## Repository Structure

```
proxmox-clawteam-general/
├── .github/
│   └── workflows/
│       └── ci.yml               # ShellCheck + BATS CI (GitHub Actions)
├── ct/
│   └── clawteam.sh              # Run on Proxmox HOST — creates the LXC
├── install/
│   └── clawteam-install.sh      # Run inside the LXC — installs all dependencies
├── test/
│   ├── bats/                    # bats-core runner (git submodule)
│   ├── test_helper/
│   │   ├── bats-support/        # output formatting (git submodule)
│   │   ├── bats-assert/         # assertion helpers (git submodule)
│   │   ├── bats-file/           # file/symlink assertions (git submodule)
│   │   ├── stub-functions.bash  # community-scripts FUNCTIONS_FILE_PATH shim
│   │   └── common-setup.bash    # shared setup(), stub helpers
│   ├── ct/
│   │   └── clawteam.bats        # Tests for ct/clawteam.sh
│   └── install/
│       └── clawteam-install.bats # Tests for install/clawteam-install.sh
└── README.md
```

## Key Files

- **`ct/clawteam.sh`**: Proxmox host script following the community-scripts/ProxmoxVE pattern.
  Creates the LXC container and delegates to the install script.

- **`install/clawteam-install.sh`**: Inside-LXC installation script. Installs:
  - System packages: git, tmux, python3, python3-venv, libzmq3-dev
  - Node.js 22 via `setup_nodejs` helper
  - OpenClaw globally via `npm install -g openclaw@latest`
  - ClawTeam in a Python virtualenv at `/opt/clawteam/.venv`
  - Systemd service `clawteam-board` for the Web dashboard on port 8080
  - Default team `openclaw-team` at `/root/workspace/openclaw-workspace`

## Conventions

- Follow the [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE) pattern for the host script
- Use `var_*` defaults for LXC settings (4 CPUs, 4 GB RAM, 10 GB disk, unprivileged)
- Call `variables` before `header_info` so `APP`/`NSAPP` are resolved first
- Use `apt-get` (not `apt`) for non-interactive package installation
- Use `npm install -g` (not `npm update`) for idempotent OpenClaw upgrades
- Use absolute paths throughout the install script — avoid bare `cd` calls
- Use `-d` / `-n` short flags for `clawteam team spawn-team` (no `--agent-name`)
- Configure a git identity before running `clawteam team spawn-team`
- Debian 13 (Trixie) as the base OS
- Symlink `clawteam` to `/usr/local/bin` after installation
- MOTD helper for usage reminders

## Dependencies

- **ClawTeam**: `pip install clawteam` — PyPI package, Python ≥ 3.10
- **ClawTeam P2P**: `pip install clawteam[p2p]` — optional ZeroMQ transport (requires `libzmq3-dev`)
- **OpenClaw**: `npm install -g openclaw` — Node.js package
- **Node.js**: Version 22
- **System packages**: git, tmux, python3, python3-venv, build-essential, libzmq3-dev

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
```

### Run integration tests (requires root inside a container)

```bash
# e.g. inside a Debian 13 container or GitHub Actions
./test/bats/bin/bats test/install/clawteam-install.bats
```

### Run with verbose output

```bash
./test/bats/bin/bats --verbose-run test/ct/clawteam.bats
```

### ShellCheck (static analysis)

```bash
shellcheck --exclude=SC1090,SC2034 ct/clawteam.sh
shellcheck --exclude=SC1090,SC2154 install/clawteam-install.sh
```

### CI

GitHub Actions runs ShellCheck and all BATS tests on every push and pull request.
Integration tests execute inside a `debian:trixie` container as root.
See `.github/workflows/ci.yml`.
