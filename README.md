# Frappe/ERPNext Installer

Automated bash installer for **Frappe v15/v16** and **ERPNext** on Ubuntu 20.04, 22.04, and 24.04.

It sets up system dependencies, Python (via **uv**), Node.js 24 (via **nvm**), MariaDB, Redis, the bench CLI, a Frappe site, and optional production services (Nginx, Supervisor, SSL).

## Requirements

- Ubuntu 20.04 / 22.04 / 24.04
- sudo access
- 4 GB RAM minimum (8 GB recommended for production)
- Internet connection

## Quick Start

```bash
git clone https://github.com/omarrtarek29/frappe-erpnext_installer
cd frappe-erpnext_installer
chmod +x frappe_installer.sh
./frappe_installer.sh
```

The wizard asks for:

| Prompt | Purpose |
|--------|---------|
| Frappe version | `15` or `16` |
| System user | Linux user that owns the bench (e.g. `frappe`) |
| Bench name | Directory name under `/home/<user>/` (e.g. `frappe-bench`) |
| Site name | Frappe site name (e.g. `site.local` or `erp.example.com`) |
| Admin password | ERPNext `Administrator` login password |
| Domain | Leave **empty** for development, or enter a domain for production + SSL |

## Development vs Production

**Development** (no domain):
- Installs the bench and site only
- Does not start services automatically
- After install, run:

```bash
cd ~/frappe-bench
bench serve --port 8000
```

Use the port shown at the end of the installer output.

**Production** (domain provided):
- Configures Nginx, Supervisor, and optional Let's Encrypt SSL
- Site is served on `https://your-domain`

## Non-Interactive Install

Copy and edit the example config:

```bash
cp config.example myconfig.conf
./frappe_installer.sh -c myconfig.conf -y
```

See `config.example` for all supported variables.

## Version Matrix

| Component | v15 | v16 |
|-----------|-----|-----|
| Python | 3.11 (uv) | 3.14 (uv) |
| Node.js | 24 (nvm) | 24 (nvm) |
| Bench CLI | uv tool | uv tool |
| Apps | Frappe + ERPNext + payments | Frappe + ERPNext |

## What the Script Does

1. Checks OS and installs system packages (MariaDB, Redis, build tools, wkhtmltopdf, etc.)
2. Installs Python, Node, Yarn, and the global `bench` command
3. Creates the bench, site, and installs ERPNext
4. Applies **dev** or **production** setup based on whether a domain was given
5. Opens firewall ports and prints a summary with next steps

## After Installation

**Development**

```bash
cd ~/frappe-bench
bench serve --port 8000
bench --site site.local console
```

**Production**

```bash
sudo supervisorctl status
sudo supervisorctl restart all
bench --site erp.example.com migrate
```

Default login: **Administrator** / password you set during install.

## Troubleshooting

- **Site not loading (dev):** Make sure `bench serve` is running and the firewall allows the port shown in the summary.
- **Site not loading (production):** Check `sudo supervisorctl status` and `sudo systemctl status nginx`.
- **SSL failed:** Confirm DNS points to this server, then run `sudo certbot --nginx -d your-domain.com`.

For other Linux distros, package names and repo setup may need manual changes.
