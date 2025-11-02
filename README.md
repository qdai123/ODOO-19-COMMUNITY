# Odoo 19 Core Mirror

This repository wraps the official Odoo 19.0 source code so it can be reused as a standalone dependency inside MOVEOPlus projects and deployed with a single provisioning script.

## Repository Source

- Upstream repository: <https://github.com/odoo/odoo> (branch `19.0`)
- Managed here as the `source` git submodule
- Current pinned commit: `e70edef8d0f5a0a588a9b0b0d306dba0f90c9d73`

Update to newer Odoo releases by checking out the desired commit inside `source/` and committing the new submodule pointer in this repository.

## Requirements

- Ubuntu 22.04 / 24.04 LTS or Debian 12
- Root privileges (`sudo`) on the target machine
- Internet access to fetch Debian/Ubuntu packages, PostgreSQL, wkhtmltopdf, and this mirror

## Using the Installer

`odoo_install.sh` provisions a fully configured Odoo 19 service. It installs system dependencies, PostgreSQL (16 by default), wkhtmltopdf, Node/rtlcss, an isolated Python virtual environment, configuration files, log directories, and a systemd unit. Optional switches enable enterprise extras, Nginx reverse proxying, and HTTPS via Certbot.

### Quick start

```bash
git clone https://github.com/qdai123/ODOO-19-COMMUNITY.git
cd ODOO-19-COMMUNITY
chmod +x odoo_install.sh
sudo ./odoo_install.sh
```

Re-run the script at any time to pull the latest mirror commits, refresh submodules, update dependencies, or regenerate the service configuration.

### Configuration toggles

Control installer behaviour by exporting environment variables before invoking the script:

| Variable | Default | Purpose |
| --- | --- | --- |
| `OE_USER` | `odoo` | System account that owns the Odoo files and service. |
| `OE_HOME_EXT` | `/odoo/odoo-19` | Destination path for the mirror checkout. |
| `OE_SERVICE_NAME` | `odoo19` | Name of the created systemd unit. |
| `OE_PORT` | `8069` | HTTP port exposed by Odoo. |
| `LONGPOLLING_PORT` | `8072` | Port used for Odoo's longpolling workers. |
| `INSTALL_POSTGRESQL_SIXTEEN` | `True` | Install PostgreSQL 16 from PostgreSQL.org packages instead of the distro version. |
| `INSTALL_WKHTMLTOPDF` | `True` | Install wkhtmltopdf (required for PDF reports). |
| `IS_ENTERPRISE` | `False` | Include extra Python dependencies used by Odoo Enterprise. |
| `INSTALL_NGINX` | `False` | Install and configure an Nginx reverse proxy. Requires `WEBSITE_NAME`. |
| `ENABLE_SSL` | `False` | Issue HTTPS certificates via Certbot when Nginx is enabled. Requires `ADMIN_EMAIL`. |
| `CUSTOM_ADDONS_DIR` | `/odoo/odoo-19/custom-addons` | Location for bespoke modules appended to the addons path. |
| `ODOO_MIRROR_URL` | `https://github.com/qdai123/ODOO-19-COMMUNITY.git` | Alternate Git remote that contains the mirror + submodule. |
| `ODOO_MIRROR_BRANCH` | `19.0` | Branch in the mirror repository to check out. |

Refer to the script header for the complete list of tunable values, including logging, superadmin password management, and mirror overrides.

### Outputs

The installer reports the final configuration, including:

- Systemd service name and status commands
- Configuration file path (default `/etc/odoo-server.conf`)
- Log directory (default `/var/log/odoo`)
- Code checkout (`/odoo/odoo-19`) and Python virtual environment (`venv`)
- Generated admin password (when `GENERATE_RANDOM_PASSWORD=True`)

Use `systemctl status odoo19` to verify that the service is running after the script completes.

## Development Notes

- The provisioning script must be run as root. It exits early with a helpful message if executed without sufficient privileges.
- When `INSTALL_POSTGRESQL_SIXTEEN=True`, the script adds the PostgreSQL APT repository, installs version 16, and enables the service. With the default setting the installer also activates the `pgvector` extension for Enterprise deployments.
- When re-running the installer on an existing host, it performs an in-place Git fetch/checkout to keep the mirror up to date and reinstalls Python requirements to match the pinned `requirements.txt`.
