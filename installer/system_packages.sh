#!/usr/bin/env bash
# System update, user creation, and package installation (Python, Node, Yarn, Redis, MariaDB)

install_system_packages() {
	log_info "Updating system packages..."
	sudo apt-get update -y
	sudo apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

	log_info "Setting up user: $FRAPPE_USER"
	if id "$FRAPPE_USER" &>/dev/null; then
		log_success "User already exists"
	else
		sudo adduser --disabled-password --gecos "" "$FRAPPE_USER"
		sudo usermod -aG sudo "$FRAPPE_USER"
		log_success "User created"
	fi

	log_info "Installing system dependencies..."
	safe_apt_install git curl wget software-properties-common
	safe_apt_install build-essential libffi-dev libssl-dev zlib1g-dev \
		libbz2-dev libreadline-dev libsqlite3-dev libncurses5-dev \
		libncursesw5-dev xz-utils tk-dev liblzma-dev

	if apt-cache show libmariadb-dev &>/dev/null; then
		safe_apt_install libmariadb-dev
	else
		safe_apt_install default-libmysqlclient-dev
	fi

	safe_apt_install libjpeg-dev libpng-dev libpq-dev
	safe_apt_install wkhtmltopdf xvfb libfontconfig ||
		log_warn "wkhtmltopdf installation failed - PDF generation may not work"
	safe_apt_install python3-pip python3-setuptools python3-venv pkg-config

	if ! command_exists pipx; then
		safe_apt_install pipx || {
			python3 -m pip install --user pipx
			python3 -m pipx ensurepath
		}
	fi

	_install_uv
	_install_python
	_install_nodejs
	_install_yarn
	_install_redis
	_install_mariadb
}

_install_uv() {
	log_info "Installing uv (Python package installer for bench)..."
	if command_exists uv; then
		log_success "uv already installed: $(uv --version 2>/dev/null || true)"
		return
	fi
	local uv_install_sh="/tmp/uv-install.sh"
	curl -LsSf https://astral.sh/uv/install.sh -o "$uv_install_sh" || {
		log_warn "uv install script download failed; bench may fall back to pip"
		rm -f "$uv_install_sh"
		return
	}
	sudo env UV_INSTALL_DIR=/usr/local/bin sh "$uv_install_sh" || {
		log_warn "uv installation failed; bench get-app may fail with 'uv not found'"
	}
	rm -f "$uv_install_sh"
	if command_exists uv; then
		log_success "uv installed: $(uv --version 2>/dev/null || true)"
	else
		log_warn "uv not in PATH; ensure /usr/local/bin is in PATH for $FRAPPE_USER"
	fi
}

_install_python() {
	log_info "Installing Python $PYTHON_VER..."

	if command_exists "python${PYTHON_VER}"; then
		log_success "Python $PYTHON_VER already installed"
	else
		if ! grep -q "deadsnakes" /etc/apt/sources.list.d/*.list 2>/dev/null; then
			sudo add-apt-repository -y ppa:deadsnakes/ppa
			sudo apt-get update -y
		fi
		safe_apt_install "python${PYTHON_VER}" "python${PYTHON_VER}-dev" "python${PYTHON_VER}-venv"
		if [ "$FRAPPE_VER" = "15" ]; then
			safe_apt_install "python${PYTHON_VER}-distutils" 2>/dev/null || true
		fi
	fi

	PYTHON_BIN=$(which "python${PYTHON_VER}")
	if [ -z "$PYTHON_BIN" ]; then
		log_error "Python $PYTHON_VER not found"
		exit 1
	fi
	log_success "Python: $PYTHON_BIN"
}

_install_nodejs() {
	log_info "Installing Node.js $NODE_VER..."

	install_nodejs() {
		log_info "Removing old Node.js installations..."
		sudo rm -f /etc/apt/sources.list.d/nodesource.list* 2>/dev/null || true
		sudo rm -f /etc/apt/keyrings/nodesource.gpg 2>/dev/null || true
		NODE_PKGS=$(dpkg -l | grep -E '^ii\s+(nodejs|npm|libnode)' | awk '{print $2}' | tr '\n' ' ') || true
		if [ -n "$NODE_PKGS" ]; then
			sudo apt-get remove -y --purge $NODE_PKGS 2>/dev/null || true
		fi
		sudo rm -rf /usr/include/node /usr/lib/node_modules 2>/dev/null || true
		sudo rm -f /usr/bin/node /usr/bin/nodejs /usr/bin/npm /usr/bin/npx 2>/dev/null || true
		sudo apt-get autoremove -y --purge 2>/dev/null || true
		sudo apt-get clean
		sudo apt-get update -y
		log_info "Installing Node.js $NODE_VER from NodeSource..."
		curl -fsSL "https://deb.nodesource.com/setup_${NODE_VER}.x" | sudo -E bash -
		sudo apt-get install -y nodejs
	}

	NEED_NODE=0
	if ! command_exists node; then
		NEED_NODE=1
	else
		CURRENT_NODE=$(node -v 2>/dev/null | cut -d. -f1 | tr -d v || echo "0")
		if [ "$CURRENT_NODE" -lt "$NODE_VER" ] 2>/dev/null; then
			NEED_NODE=1
		fi
	fi

	[ "$NEED_NODE" = "1" ] && install_nodejs

	if ! command_exists node; then
		log_error "Node.js installation failed"
		exit 1
	fi
	log_success "Node.js $(node -v)"
}

_install_yarn() {
	log_info "Installing Yarn..."
	sudo npm install -g npm@latest 2>/dev/null || true
	if ! command_exists yarn; then
		sudo npm install -g yarn
	fi
	log_success "Yarn $(yarn --version)"
}

_install_redis() {
	log_info "Installing Redis..."
	if ! command_exists redis-server; then
		safe_apt_install redis-server
	fi
	sudo systemctl enable redis-server 2>/dev/null || true
	sudo systemctl start redis-server 2>/dev/null || true
	if redis-cli ping &>/dev/null; then
		log_success "Redis is running"
	else
		log_warn "Redis may not be running properly"
	fi
}

_install_mariadb() {
	log_info "Installing MariaDB..."
	if ! command_exists mariadb; then
		safe_apt_install mariadb-server mariadb-client
	fi
	sudo systemctl enable mariadb 2>/dev/null || true
	sudo systemctl start mariadb 2>/dev/null || true
}
