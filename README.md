# Odoo 19 Core Mirror

This repository wraps the official Odoo 19.0 source code so it can be consumed as a standalone dependency inside MOVEOPlus projects.

## Repository Source

- Upstream repository: <https://github.com/odoo/odoo> (branch `19.0`)
- Managed here as the `source` git submodule
- Current pinned commit: `6e5146113adbdce3cbe317a7b3ef16be0a244b6a`

## Getting Started

```bash
git clone git@github.com:phatdangminh/odoo19.git
cd odoo19
git submodule update --init --recursive
```

The upstream code lives under the `source/` directory. Update to newer Odoo releases by pulling the desired commit inside `source` and committing the submodule pointer in this repository.

## Provisioning Script

Use the bundled `odoo_install.sh` to bootstrap an Odoo 19 instance on Ubuntu 22.04/24.04 or Debian 12 servers. The script:

- Installs PostgreSQL 16 (or distro default), wkhtmltopdf, Node/rtlcss, and core build tools.
- Clones this mirror plus the `source/` submodule under `/odoo/odoo-19`.
- Sets up a Python virtual environment, Odoo config in `/etc/odoo-server.conf`, log directory, and a systemd unit.
- Optionally enables enterprise extras, Nginx reverse proxying, and certbot-based HTTPS.

### Usage

```bash
chmod +x odoo_install.sh
sudo ./odoo_install.sh
```

Override defaults by exporting environment variables before running, for example:

```bash
export INSTALL_NGINX=True
export WEBSITE_NAME=moveoplus.com
export ADMIN_EMAIL=info@moveoplus.com
sudo ./odoo_install.sh
```

Review the script header for the full list of tunable variables (e.g., `OE_PORT`, `INSTALL_POSTGRESQL_SIXTEEN`, `IS_ENTERPRISE`).
