# Frappe/ERPNext v16 Automated Installer

A simple, automated bash script to install **Frappe Framework** and **ERPNext v16** on Ubuntu systems with minimal manual intervention.

## Features

- ✅ Automated installation of all dependencies
- ✅ Python 3.14 support
- ✅ Node.js 24 installation
- ✅ MariaDB setup with interactive or existing password support
- ✅ Bench initialization and ERPNext app installation
- ✅ Production-ready setup with Nginx and Supervisor
- ✅ Optional SSL certificate setup with Let's Encrypt
- ✅ UFW firewall configuration

## Prerequisites

- **Operating System**: Ubuntu 20.04 / 22.04 / 24.04 (fresh installation recommended)
- **User Access**: Root or sudo privileges
- **RAM**: Minimum 4GB (8GB recommended for production)
- **Storage**: Minimum 40GB free disk space
- **Network**: Active internet connection

## Quick Start

### Step 1: Download the Script

```bash
# Download the script
wget https://github.com/omarrtarek29/frappe-erpnext_installer/blob/main/frappe_installer.sh

# Or if you have it locally, just navigate to its directory
cd /path/to/script
```

### Step 2: Make it Executable

```bash
chmod +x frappe_installer.sh
```

### Step 3: Run the Installer

```bash
sudo ./frappe_installer.sh
```

## Installation Process

When you run the script, you'll be prompted for the following information:

### 1. **Frappe System User**
```
Enter frappe system user: frappe
```
- This is the Linux user that will own and run the Frappe/ERPNext application
- Default recommendation: `frappe`
- The script will create this user if it doesn't exist

### 2. **Bench Path**
```
Enter bench path (example: /home/frappe/frappe-bench): /home/frappe/frappe-bench
```
- Full path where the Frappe bench will be installed
- Format: `/home/[username]/frappe-bench`
- Example: `/home/frappe/frappe-bench`

### 3. **Site Name**
```
Enter site name: mysite.local
```
- Domain name for your ERPNext site
- For local/development: use `.local` domain (e.g., `mysite.local`)
- For production: use your actual domain (e.g., `erp.mycompany.com`)

### 4. **Admin Password**
```
Enter admin password for Frappe site: 
```
- Password for the Administrator account in ERPNext
- This is what you'll use to log in after installation
- Choose a strong password

### 5. **Domain (Optional)**
```
Enter domain (leave empty to skip SSL): 
```
- If you have a registered domain and want SSL (HTTPS)
- Enter your domain name (e.g., `erp.mycompany.com`)
- Leave empty to skip SSL setup
- **Note**: Domain must be pointing to your server's IP address

### 6. **MariaDB Setup**

The script will ask:
```
Do you already have a MariaDB root password set? (y/n):
```

#### Option A: You Already Have a Password (answer: y)
```
Enter your existing MariaDB root password: 
```
- Enter your existing MariaDB root password
- The script will verify it before continuing

#### Option B: First Time Setup (answer: n)

The script will guide you through `mysql_secure_installation`:

1. **Enter current password for root**: Press `ENTER` (no password set yet)
2. **Switch to unix_socket authentication**: Type `y` and press `ENTER`
3. **Change the root password**: Type `y`, then enter your new password twice
4. **Remove anonymous users**: Type `y`
5. **Disallow root login remotely**: Type `n`
6. **Remove test database**: Type `y`
7. **Reload privilege tables**: Type `y`

After completion, the script will ask:
```
Enter the MariaDB root password you just set:
```
Enter the password you created during the secure installation.

## What Gets Installed

The script automatically installs and configures:

### System Packages
- Git, curl, wget, nano
- Software Properties Common
- MariaDB Server & Client
- Redis Server
- wkhtmltopdf (for PDF generation)
- Build essentials and development libraries

### Programming Languages & Tools
- **Python 3.14** with development headers and venv
- **Node.js 24** (latest LTS)
- **Yarn** package manager
- **uv** (fast Python package installer)

### Frappe Stack
- **Frappe Bench** (CLI tool for managing Frappe applications)
- **Frappe Framework v16**
- **ERPNext v16** (full ERP application)

### Production Services
- **Nginx** (web server and reverse proxy)
- **Supervisor** (process manager for background workers)
- **UFW Firewall** (configured to allow ports 22, 80, 443, 8000)

### Optional
- **Certbot** (for SSL/TLS certificates via Let's Encrypt)

## Post-Installation

After successful installation, you'll see:

```
=======================================
 FRAPPE/ERPNEXT INSTALLATION COMPLETE 
=======================================
 Bench Path: /home/frappe/frappe-bench
 Site Name : mysite.local
 Python    : /usr/bin/python3.14
 Access URL: http://YOUR_SERVER_IP
 Domain    : https://yourdomain.com (if configured)
=======================================
```

### Accessing ERPNext

1. Open your web browser
2. Navigate to:
   - **Without domain**: `http://YOUR_SERVER_IP`
   - **With domain**: `https://yourdomain.com`

3. Login with:
   - **Username**: `Administrator`
   - **Password**: The admin password you set during installation

## Useful Commands

After installation, here are some helpful commands:

### Navigate to Bench Directory
```bash
cd /home/frappe/frappe-bench
```

### Start in Development Mode
```bash
bench start
```
This starts all services in the foreground (useful for development/testing)

### Restart in Production Mode
```bash
bench restart
```

### Check Service Status
```bash
sudo supervisorctl status
```

### Restart All Services
```bash
sudo supervisorctl restart all
```

### List Installed Apps
```bash
bench --site mysite.local list-apps
```

### Check Bench Status
```bash
bench version
```

### View Logs
```bash
# Nginx access logs
sudo tail -f /var/log/nginx/access.log

# Nginx error logs
sudo tail -f /var/log/nginx/error.log

# Supervisor logs
sudo tail -f /var/log/supervisor/supervisord.log
```

## Troubleshooting

### Can't Access the Site

1. Check if services are running:
   ```bash
   sudo supervisorctl status
   ```

2. Check Nginx status:
   ```bash
   sudo systemctl status nginx
   ```

3. Check firewall:
   ```bash
   sudo ufw status
   ```

### Supervisor Issues

If you encounter supervisor-related issues or services are not starting:

```bash
cd /home/frappe/frappe-bench
sudo bench setup production [$FRAPPE_USER]
```

This will reconfigure supervisor and nginx for production.

### SSL Certificate Issues

If SSL certificate installation failed or you need to reinstall it:

```bash
sudo certbot --nginx -d yourdomain.com
```

Make sure your domain's DNS A record is pointing to your server's IP address before running this command.

### MariaDB Connection Issues

1. Verify MariaDB is running:
   ```bash
   sudo systemctl status mariadb
   ```

2. Test connection:
   ```bash
   sudo mysql -uroot -p
   ```

---

**Note**: This script is designed for Ubuntu systems. For other Linux distributions, you may need to modify package manager commands and package names accordingly.
