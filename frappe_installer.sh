#!/usr/bin/env bash
set -e

###########################################
# USER INPUT
###########################################
read -p "Enter Frappe version (15 or 16): " FRAPPE_VER
if [ "$FRAPPE_VER" != "15" ] && [ "$FRAPPE_VER" != "16" ]; then
    echo "Invalid version. Enter 15 or 16."
    exit 1
fi

read -p "Enter frappe system user: " FRAPPE_USER
read -p "Enter bench name (example: frappe-bench): " BENCH_NAME
read -p "Enter site name: " SITE_NAME
read -p "Enter admin password for Frappe site: " ADMIN_PASS
read -p "Enter domain (leave empty to skip SSL): " DOMAIN


if [ "$FRAPPE_VER" = "15" ]; then
    PYTHON_MINOR="3.10"
    FRAPPE_BRANCH="version-15"
else
    PYTHON_MINOR="3.14"
    FRAPPE_BRANCH="version-16"
fi

###########################################
echo "=== Update System ==="
sudo apt-get update -y
sudo apt-get upgrade -y

###########################################
echo "=== Create frappe user if missing ==="
if id "$FRAPPE_USER" &>/dev/null; then
    echo "User '$FRAPPE_USER' already exists, skipping creation."
else
    sudo adduser --disabled-password --gecos "" "$FRAPPE_USER"
    sudo usermod -aG sudo "$FRAPPE_USER"
    echo "User '$FRAPPE_USER' created."
fi

###########################################
echo "=== Install system dependencies ==="
sudo apt-get install -y \
git curl wget nano \
software-properties-common \
mariadb-server mariadb-client \
redis-server \
wkhtmltopdf xvfb libfontconfig \
libmysqlclient-dev libpq-dev \
libffi-dev libssl-dev \
zlib1g-dev libjpeg-dev \
pkg-config python3-pip python3-setuptools pipx

###########################################
echo "=== Install Python ${PYTHON_MINOR} ==="
if ! command -v python${PYTHON_MINOR} &>/dev/null; then
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    sudo apt-get update -y
    sudo apt-get install -y \
    python${PYTHON_MINOR} \
    python${PYTHON_MINOR}-dev \
    python${PYTHON_MINOR}-venv
fi

if [ "$FRAPPE_VER" = "15" ]; then
    sudo apt-get install -y python3.10-setuptools 2>/dev/null || true
fi
PYTHON_BIN=$(which python${PYTHON_MINOR})
echo "Using Python: $PYTHON_BIN"

cd /tmp 2>/dev/null || true

###########################################
echo "=== Install Node 24 ==="
NEED_NODE=0
if ! command -v node &>/dev/null; then
    NEED_NODE=1
elif [ "$(node -v 2>/dev/null | cut -d. -f1 | tr -d v)" -lt 24 ] 2>/dev/null; then
    NEED_NODE=1
fi
if [ "$NEED_NODE" = "1" ]; then
    curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

###########################################
echo "=== Install Yarn ==="
if ! command -v sudo npm &>/dev/null; then
    sudo npm install -g npm
    sudo npm install -g yarn
fi

###########################################
echo "=== Install uv (required by Bench) ==="
if ! command -v uv &>/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    if [ -f "$HOME/.local/bin/uv" ]; then
        sudo ln -sf "$HOME/.local/bin/uv" /usr/local/bin/uv 2>/dev/null || true
    fi
    if [ -f /root/.local/bin/uv ]; then
        sudo ln -sf /root/.local/bin/uv /usr/local/bin/uv 2>/dev/null || true
    fi
    sudo -u "$FRAPPE_USER" bash -c "curl -LsSf https://astral.sh/uv/install.sh | sh"
fi

###########################################
echo ""
echo "=== MariaDB Setup ==="
echo ""

MYSQL_ROOT_PASS=""
PASSWORD_SET=false

read -p "Do you already have a MariaDB root password set? (y/n): " HAS_PASSWORD

if [ "$HAS_PASSWORD" = "y" ] || [ "$HAS_PASSWORD" = "Y" ]; then
    while true; do
        read -s -p "Enter your existing MariaDB root password: " MYSQL_ROOT_PASS
        echo
        
        if sudo mysql -uroot -p"$MYSQL_ROOT_PASS" -e "SELECT 1;" &>/dev/null; then
            echo "✓ MariaDB password verified successfully"
            PASSWORD_SET=true
            break
        else
            echo "✗ Incorrect password. Please try again."
            read -p "Try again? (y/n): " RETRY
            if [ "$RETRY" != "y" ] && [ "$RETRY" != "Y" ]; then
                echo "Exiting..."
                exit 1
            fi
        fi
    done
else
    echo ""
    echo "We will now secure your MariaDB installation."
    echo "You will be prompted to:"
    echo "  1. Enter current password (just press ENTER)"
    echo "  2. Switch to unix_socket authentication (answer: y)"
    echo "  3. Change root password (answer: y, then enter your new password)"
    echo "  4. Remove anonymous users (answer: y)"
    echo "  5. Disallow root login remotely (answer: n)"
    echo "  6. Remove test database (answer: y)"
    echo "  7. Reload privilege tables (answer: y)"
    echo ""
    read -p "Press ENTER to continue..."
    
    sudo mysql_secure_installation
    
    while true; do
        echo ""
        read -s -p "Enter the MariaDB root password you just set: " MYSQL_ROOT_PASS
        echo
        
        if sudo mysql -uroot -p"$MYSQL_ROOT_PASS" -e "SELECT 1;" &>/dev/null; then
            echo "✓ MariaDB password verified successfully"
            PASSWORD_SET=true
            break
        else
            echo "✗ Cannot connect with that password. Please try again."
            read -p "Try again? (y/n): " RETRY
            if [ "$RETRY" != "y" ] && [ "$RETRY" != "Y" ]; then
                echo "Exiting..."
                exit 1
            fi
        fi
    done
fi

if [ "$PASSWORD_SET" = false ]; then
    echo "ERROR: MariaDB password not set correctly"
    exit 1
fi

###########################################
echo ""
echo "=== Configure MariaDB ==="

sudo tee /etc/mysql/mariadb.conf.d/99-frappe.cnf > /dev/null <<'EOF'
[mysqld]
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
EOF

echo "Restarting MariaDB with new configuration..."
if sudo systemctl restart mariadb; then
    echo "✓ MariaDB restarted successfully"
    sleep 3
else
    echo "✗ MariaDB failed to restart, removing custom config..."
    sudo rm /etc/mysql/mariadb.conf.d/99-frappe.cnf
    sudo systemctl restart mariadb
    echo "MariaDB restored, continuing without custom character set config"
fi

sudo mysql -uroot -p"$MYSQL_ROOT_PASS" -e "SET GLOBAL character_set_server='utf8mb4';" 2>/dev/null || true
sudo mysql -uroot -p"$MYSQL_ROOT_PASS" -e "SET GLOBAL collation_server='utf8mb4_unicode_ci';" 2>/dev/null || true

###########################################
echo ""
echo "=== Install Bench under frappe user ==="
sudo -u $FRAPPE_USER -H bash <<EOF
set -e

export PATH=/home/$FRAPPE_USER/.local/bin:\$PATH

# Ensure pipx is available
pipx ensurepath || true

if ! command -v bench &>/dev/null; then
    echo "Installing frappe-bench..."
    pipx install frappe-bench
fi

bench --version
EOF

###########################################
echo ""
echo "=== Init Bench & Create Site ==="
sudo -u $FRAPPE_USER -H bash <<EOF
set -e

export PATH=/home/$FRAPPE_USER/.local/bin:\$PATH

cd /home/$FRAPPE_USER

if [ ! -d "/home/$FRAPPE_USER/$BENCH_NAME" ]; then
    echo "Initializing new bench at /home/$FRAPPE_USER/$BENCH_NAME..."
    bench init "/home/$FRAPPE_USER/$BENCH_NAME" --python "$PYTHON_BIN" --frappe-branch $FRAPPE_BRANCH
else
    echo "Bench already exists at /home/$FRAPPE_USER/$BENCH_NAME"
fi

cd "/home/$FRAPPE_USER/$BENCH_NAME"

# v15 requires payments app before ERPNext
if [ "$FRAPPE_VER" = "15" ] && [ ! -d "apps/payments" ]; then
    echo "Getting payments app..."
    bench get-app payments --branch $FRAPPE_BRANCH
fi

# Get ERPNext app
if [ ! -d "apps/erpnext" ]; then
    echo "Getting ERPNext app..."
    bench get-app erpnext --branch $FRAPPE_BRANCH
else
    echo "ERPNext app already exists"
fi

# v15: force-install setuptools in bench venv (dropbox needs pkg_resources)
if [ "$FRAPPE_VER" = "15" ]; then
    echo "Installing setuptools<75 in bench venv (pkg_resources for v15)..."
    ./env/bin/python -m ensurepip --upgrade 2>/dev/null || true
    ./env/bin/python -m pip install "setuptools>=58,<75"
    ./env/bin/python -c "import pkg_resources; print('pkg_resources OK')" || { echo "ERROR: pkg_resources still missing"; exit 1; }
fi

# Create site if it doesn't exist
if [ ! -d "sites/$SITE_NAME" ]; then
    echo "Creating new site: $SITE_NAME ..."
    bench new-site $SITE_NAME \
    --admin-password "$ADMIN_PASS" \
    --mariadb-root-password "$MYSQL_ROOT_PASS"
else
    echo "Site $SITE_NAME already exists"
fi
EOF

###########################################
echo ""
echo "=== Setup Firewall ==="
if command -v ufw &>/dev/null; then
    sudo ufw allow 22,80,443,8000/tcp
    sudo ufw --force enable
else
    echo "ufw not installed, skipping firewall setup"
fi

###########################################
if [ ! -z "$DOMAIN" ]; then
    echo ""
    echo "=== Setup Production ==="
    cd "/home/$FRAPPE_USER/$BENCH_NAME"
    sudo -E env "PATH=/home/$FRAPPE_USER/.local/bin:$PATH" bench setup production $FRAPPE_USER

    sleep 3
    sudo supervisorctl reread || true
    sudo supervisorctl update || true
    sudo supervisorctl restart all || true

    echo ""
    echo "=== Install SSL ==="
    sudo snap install core || true
    sudo snap refresh core || true
    sudo snap install --classic certbot || true
    sudo ln -sf /snap/bin/certbot /usr/bin/certbot || true
    
    echo "Attempting to install SSL certificate..."
    if sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email 2>/dev/null; then
        echo "✓ SSL certificate installed successfully"
    elif sudo certbot --nginx -d $DOMAIN 2>/dev/null; then
        echo "✓ SSL certificate installed successfully"
    else
        echo "⚠ SSL certificate installation failed (likely DNS not configured)"
        echo "You can install SSL later by running: sudo certbot --nginx -d $DOMAIN"
    fi

    ###########################################
    echo ""
    echo "=== Install ERPNext ==="
    sudo -u $FRAPPE_USER -H bash <<EOF
export PATH=/home/$FRAPPE_USER/.local/bin:\$PATH
cd "/home/$FRAPPE_USER/$BENCH_NAME"
echo "Installing ERPNext on site..."
bench --site $SITE_NAME install-app erpnext
bench --site $SITE_NAME enable-scheduler
bench --site $SITE_NAME set-maintenance-mode off
EOF

    sudo supervisorctl restart all || true

else
    echo ""
    echo "=== Starting Bench in Background ==="
    sudo -u $FRAPPE_USER -H bash <<EOF
export PATH=/home/$FRAPPE_USER/.local/bin:\$PATH
cd "/home/$FRAPPE_USER/$BENCH_NAME"

# Start bench in background
nohup bench start > bench_start.log 2>&1 &
BENCH_PID=\$!
echo "Bench started with PID: \$BENCH_PID"

# Wait for Redis to be ready
echo "Waiting for Redis to start..."
sleep 10

# Install ERPNext
echo "Installing ERPNext on site..."
bench --site $SITE_NAME install-app erpnext
bench --site $SITE_NAME enable-scheduler
bench --site $SITE_NAME set-maintenance-mode off

echo "ERPNext installation complete!"
echo "Bench is running in background (PID: \$BENCH_PID)"
echo "To stop bench: kill \$BENCH_PID"
echo "To view logs: tail -f /home/$FRAPPE_USER/$BENCH_NAME/bench_start.log"
EOF
fi

echo ""
echo "======================================="
echo " FRAPPE/ERPNEXT INSTALLATION COMPLETE "
echo "======================================="
echo " Version   : Frappe $FRAPPE_VER ($FRAPPE_BRANCH)"
echo " Bench Path: /home/$FRAPPE_USER/$BENCH_NAME"
echo " Site Name : $SITE_NAME"
echo " Python    : $PYTHON_BIN"
echo " Access URL: http://$(hostname -I | awk '{print $1}')"
if [ ! -z "$DOMAIN" ]; then
    echo " Domain    : https://$DOMAIN"
fi
echo "======================================="
echo ""
echo "Useful commands:"
echo "  cd /home/$FRAPPE_USER/$BENCH_NAME"
echo "  bench start              # Start in development mode"
echo "  bench restart            # Restart in production mode"
echo "  sudo supervisorctl status # Check service status"
echo "  bench --site $SITE_NAME list-apps"
echo ""
echo "Login credentials:"
echo "  Username: Administrator"
echo "  Password: $ADMIN_PASS"
echo ""
