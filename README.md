# Frappe/ERPNext Installer

Get a working **Frappe v15 or v16** bench, with **ERPNext**, on a fresh Ubuntu server. One script installs the runtime Frappe expects (Python via **uv**, Node.js via **nvm**, MariaDB, Redis, wkhtmltopdf), creates the bench and site, then leaves you in development mode or production with Nginx, Supervisor, and optional Let's Encrypt.

A first install usually takes **15–40 minutes**, mostly while bench downloads Frappe and ERPNext.

## Who it is for

- **Frappe and ERPNext developers** who want a bench for app work without assembling the manual install by hand.
- **Teams** that stand up staging, demo, or client environments and want the same steps every time.
- **Operators** deploying one production site on an Ubuntu VPS, with a domain and HTTPS.

If your team already runs [frappe_docker](https://github.com/frappe/frappe_docker), keep using that. This installer builds a normal bench on the host.

## What it takes care of

Frappe fails in confusing ways when Python, Node, or MariaDB are only "close enough". The installer pins the versions current Frappe releases require:

| | Frappe v15 | Frappe v16 |
|--|------------|------------|
| Python (uv) | 3.11 | 3.14 |
| Node.js (nvm) | 24 | 24 |
| MariaDB | 10.6+ | 11.8 |
| Apps | Frappe and ERPNext | Frappe and ERPNext |
| Ubuntu | 20.04, 22.04, 24.04, 26.04 | 20.04, 22.04, 24.04, 26.04 |

The installer reads the Ubuntu release before it installs anything. Ubuntu 26.04 already ships MariaDB 11.8, so both Frappe versions use that package. Ubuntu 20.04's own MariaDB is 10.3, so v15 and v16 install MariaDB from the MariaDB repository. The live 11.8 mirror has no Ubuntu 20.04 suite; the installer uses the MariaDB archive for that release. 22.04 and 24.04 use a MariaDB repo only when the distro package is too old.

## Requirements

- Ubuntu 20.04, 22.04, 24.04, or 26.04
- A user with sudo, or root
- 4 GB RAM minimum (8 GB is safer for production)
- 8 GB free on `/` (a 20 GB disk is a practical minimum)
- A public DNS name only if you want production HTTPS

Interactive installs can prompt for your sudo password. Non-interactive installs (`-y`) need passwordless sudo, or to be run as root.

## Quick start

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
| System user | Linux user that owns the bench (for example `frappe`) |
| Bench name | Directory under `/home/<user>/` (default `frappe-bench`) |
| Site name | `site.local` for development, or your hostname |
| Admin password | ERPNext `Administrator` password |
| Domain | Leave empty for development. Set it for production and SSL |
| ERPNext | Install ERPNext on the site, or leave a Frappe-only bench |

### Development

Leave the domain empty. When the script finishes, start the site yourself:

```bash
cd ~/frappe-bench
bench serve --port 8000
```

Open the URL printed at the end. Log in as **Administrator** with the password you chose.

### Production

Enter a domain that already points at this server. The installer configures Nginx and Supervisor, then requests a Let's Encrypt certificate. The site is served at `https://your-domain`.

Set `SSL_EMAIL` in the config file if you want expiry notices. Without it, Certbot still runs, and renewal emails are skipped.

## Use cases

**App development.** Spin up v15 or v16 on a laptop VM or a small VPS, skip the domain, and use `bench serve`, `bench console`, and `bench get-app` for a custom app.

**Staging that matches production.** Use the same version, the same Ubuntu release, and a hostname. Give the staging box a domain when you want Nginx and HTTPS, or leave the domain empty when you only need `bench serve`.

**A single production site.** Point DNS at the server, pass the domain, and let the script install ERPNext, enable the scheduler, and open ports 80 and 443.

**Repeatable client or demo benches.** Check in a private config (without committing real passwords) and run:

```bash
cp config.example myconfig.conf
./frappe_installer.sh -c myconfig.conf -y
```

`MYSQL_ROOT_PASS` is required with `-y`. The config file is sourced as shell, so keep it private and do not point it at a file you do not trust.

Payment gateway apps are not installed by default. After the bench exists:

```bash
cd ~/frappe-bench
bench get-app payments --branch version-15
bench --site site.local install-app payments
```

Use `version-16` on a v16 bench.

## What the script does

1. Checks the OS and installs system packages, including MariaDB, Redis, cron, wkhtmltopdf, Nginx, and Supervisor.
2. Installs Python, Node, Yarn, and the `bench` command.
3. Creates the bench and site, then installs ERPNext when you asked for it.
4. Starts development instructions, or production services, based on whether a domain was given.
5. Opens the SSH port that is actually in use, plus the web ports for the mode you chose.
6. Prints the URL, login, and a link to send feedback.

`FORCE_SITE=yes` recreates the named site on a bench that already exists. That drops the site database. It is for rebuilding a site, not for upgrading Frappe.

## After installation

**Development**

```bash
cd ~/frappe-bench
bench serve --port 8000
bench --site site.local console
bench --site site.local mariadb
```

**Production**

```bash
sudo supervisorctl status
sudo supervisorctl restart all
cd ~/frappe-bench
bench --site erp.example.com migrate
bench --site erp.example.com backup
```

## Troubleshooting

- **Site not loading (dev):** `bench serve` has to be running. Use the port from the summary, and confirm the firewall allows it.
- **Site not loading (production):** `sudo supervisorctl status` and `sudo systemctl status nginx`.
- **SSL failed:** DNS must point at this server before Certbot can succeed. Retry with `sudo certbot --nginx -d your-domain.com`.
- **Ubuntu 20.04 and MariaDB 11.8:** the installer uses the MariaDB archive when the live mirror has no `focal` suite.
- **Disk full during `yarn install` (`ENOSPC`):** the root volume is too small. Expand it to at least 20 GB and run the installer again. The preflight check stops before install when less than 8 GB is free.
- **Bench directory already exists:** pick another `BENCH_NAME`, or set `FORCE_SITE=yes` only when you mean to recreate that site.

## Feedback

Install reports are how this project gets better. If you tried it, open an issue and include:

- Ubuntu release and Frappe version (`15` or `16`)
- Development or production
- The command you ran
- The first error, with secrets removed

[Open an install report](https://github.com/omarrtarek29/frappe-erpnext_installer/issues/new/choose)

Bug fixes and small docs improvements are welcome as pull requests. Ideas for where to share the project with other Frappe and ERPNext developers are in [COMMUNITY.md](COMMUNITY.md).

## License

[MIT](LICENSE)
