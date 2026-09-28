#!/usr/bin/env bash

install_system_packages() {
	log_info "Updating system packages..."
	apt_cmd="sudo apt-get"
	[ "$EUID" -eq 0 ] && apt_cmd="apt-get"

	$apt_cmd update -y
	$apt_cmd upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

	log_info "Setting up user: $FRAPPE_USER"
	if id "$FRAPPE_USER" &>/dev/null; then
		log_success "User $FRAPPE_USER already exists"
	else
		if [ "$EUID" -eq 0 ]; then
			adduser --disabled-password --gecos "" "$FRAPPE_USER"
			usermod -aG sudo "$FRAPPE_USER"
		else
			sudo adduser --disabled-password --gecos "" "$FRAPPE_USER"
			sudo usermod -aG sudo "$FRAPPE_USER"
		fi
		log_success "User $FRAPPE_USER created"
	fi

	_configure_frappe_sudoers

	# Nginx only needs to traverse the home directory. Recursive world-read
	# would expose SSH keys and site config to every local user.
	sudo chmod o+x "/home/$FRAPPE_USER"
	log_success "Home directory traversal set for nginx"

	log_info "Installing system dependencies..."
	safe_apt_install git curl wget software-properties-common
	local ncurses_packages="libncurses5-dev libncursesw5-dev"
	. /etc/os-release 2>/dev/null || true
	if [ "${VERSION_ID:-}" = "26.04" ]; then
		ncurses_packages="libncurses-dev"
	fi
	safe_apt_install build-essential libffi-dev libssl-dev zlib1g-dev \
		libbz2-dev libreadline-dev libsqlite3-dev $ncurses_packages \
		xz-utils tk-dev liblzma-dev

	if apt-cache show libmariadb-dev &>/dev/null; then
		safe_apt_install libmariadb-dev
	else
		safe_apt_install default-libmysqlclient-dev
	fi

	safe_apt_install libjpeg-dev libpng-dev libpq-dev
	safe_apt_install python3-pip python3-setuptools python3-venv pkg-config
	safe_apt_install xvfb libfontconfig

	_install_uv
	_install_python
	_install_nodejs
	_install_yarn
	_install_wkhtmltopdf
	_install_redis
	_install_mariadb
	safe_apt_install supervisor nginx ansible cron fail2ban
	sudo systemctl enable supervisor nginx 2>/dev/null || true
}

_configure_frappe_sudoers() {
	local file="/etc/sudoers.d/$FRAPPE_USER"
	local tmp
	tmp="$(mktemp)"
	cat > "$tmp" <<EOF
# Service management for bench. Full NOPASSWD root is intentionally not granted.
$FRAPPE_USER ALL=(ALL) NOPASSWD: /usr/bin/supervisorctl, /usr/sbin/nginx, /usr/bin/certbot, /bin/systemctl start nginx, /bin/systemctl stop nginx, /bin/systemctl restart nginx, /bin/systemctl reload nginx, /bin/systemctl start supervisor, /bin/systemctl stop supervisor, /bin/systemctl restart supervisor, /bin/systemctl reload supervisor, /usr/sbin/service nginx *, /usr/sbin/service supervisor *
EOF
	sudo cp "$tmp" "$file"
	sudo chown root:root "$file"
	sudo chmod 440 "$file"
	rm -f "$tmp"
	if ! sudo visudo -cf "$file"; then
		sudo rm -f "$file"
		log_error "Refusing to keep an invalid sudoers file for $FRAPPE_USER"
		exit 1
	fi
	log_success "Limited sudoers rule installed for $FRAPPE_USER"
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
	log_info "Installing Python $PYTHON_VER via uv..."

	if ! command_exists uv; then
		log_error "uv is required but not installed"
		exit 1
	fi

	log_info "Installing Python $PYTHON_VER for $FRAPPE_USER..."
	sudo -u "$FRAPPE_USER" -H bash -c "
		export PATH=\"/usr/local/bin:\$HOME/.local/bin:\$PATH\"
		uv python install $PYTHON_VER
	" || {
		log_error "Failed to install Python $PYTHON_VER via uv"
		exit 1
	}

	PYTHON_BIN=$(sudo -u "$FRAPPE_USER" -H bash -c "
		export PATH=\"/usr/local/bin:\$HOME/.local/bin:\$PATH\"
		uv python find $PYTHON_VER 2>/dev/null
	")

	if [ -z "$PYTHON_BIN" ] || [ ! -x "$PYTHON_BIN" ]; then
		log_error "Python $PYTHON_VER not found after uv install"
		exit 1
	fi

	export PYTHON_BIN
	log_success "Python: $PYTHON_BIN"
}

_install_nodejs() {
	log_info "Installing Node.js $NODE_VER via nvm..."

	log_info "Removing old system Node.js installations..."
	sudo rm -f /etc/apt/sources.list.d/nodesource.list* 2>/dev/null || true
	sudo rm -f /etc/apt/keyrings/nodesource.gpg 2>/dev/null || true
	NODE_PKGS=$(dpkg -l | grep -E '^ii\s+(nodejs|npm|libnode)' | awk '{print $2}' | tr '\n' ' ') || true
	if [ -n "$NODE_PKGS" ]; then
		sudo apt-get remove -y --purge $NODE_PKGS 2>/dev/null || true
	fi
	sudo rm -rf /usr/include/node /usr/lib/node_modules 2>/dev/null || true
	sudo rm -f /usr/bin/node /usr/bin/nodejs /usr/bin/npm /usr/bin/npx 2>/dev/null || true
	sudo rm -f /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx 2>/dev/null || true

	log_info "Installing nvm for $FRAPPE_USER..."
	sudo -u "$FRAPPE_USER" -H bash -c '
		export HOME="/home/'"$FRAPPE_USER"'"
		curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
	' || {
		log_error "Failed to install nvm"
		exit 1
	}

	log_info "Installing Node.js $NODE_VER..."
	sudo -u "$FRAPPE_USER" -H bash -c '
		export HOME="/home/'"$FRAPPE_USER"'"
		export NVM_DIR="$HOME/.nvm"
		[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
		nvm install '"$NODE_VER"'
		nvm use '"$NODE_VER"'
		nvm alias default '"$NODE_VER"'
	' || {
		log_error "Failed to install Node.js $NODE_VER"
		exit 1
	}

	local node_bin_dir
	node_bin_dir=$(sudo -u "$FRAPPE_USER" -H bash -c '
		export HOME="/home/'"$FRAPPE_USER"'"
		export NVM_DIR="$HOME/.nvm"
		[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
		dirname "$(nvm which '"$NODE_VER"')"
	')

	if [ -z "$node_bin_dir" ] || [ ! -d "$node_bin_dir" ]; then
		log_error "Could not find Node.js bin directory"
		exit 1
	fi

	log_info "Creating symlinks in /usr/local/bin..."
	for bin in node npm npx; do
		if [ -x "$node_bin_dir/$bin" ]; then
			sudo ln -sf "$node_bin_dir/$bin" /usr/local/bin/$bin
		fi
	done

	if ! /usr/local/bin/node --version &>/dev/null; then
		log_error "Node.js symlink verification failed"
		exit 1
	fi

	log_success "Node.js $(/usr/local/bin/node -v)"
}

_install_yarn() {
	log_info "Installing Yarn..."

	local node_bin_dir
	node_bin_dir=$(sudo -u "$FRAPPE_USER" -H bash -c '
		export HOME="/home/'"$FRAPPE_USER"'"
		export NVM_DIR="$HOME/.nvm"
		[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
		dirname "$(nvm which '"$NODE_VER"')"
	')

	sudo -u "$FRAPPE_USER" -H bash -c '
		export HOME="/home/'"$FRAPPE_USER"'"
		export NVM_DIR="$HOME/.nvm"
		[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
		npm install -g yarn
	' || {
		log_error "Failed to install yarn"
		exit 1
	}

	if [ -x "$node_bin_dir/yarn" ]; then
		sudo ln -sf "$node_bin_dir/yarn" /usr/local/bin/yarn
	fi

	if ! /usr/local/bin/yarn --version &>/dev/null; then
		log_error "Yarn symlink verification failed"
		exit 1
	fi

	log_success "Yarn $(/usr/local/bin/yarn --version)"
}

_install_wkhtmltopdf() {
	log_info "Installing wkhtmltopdf (patched Qt version)..."

	if command_exists wkhtmltopdf; then
		local wk_ver
		wk_ver=$(wkhtmltopdf --version 2>&1 || true)
		if echo "$wk_ver" | grep -q "patched qt"; then
			log_success "wkhtmltopdf (patched qt) already installed"
			return 0
		fi
		log_info "Removing non-patched wkhtmltopdf..."
		sudo apt-get remove -y --purge wkhtmltopdf 2>/dev/null || true
	fi

	local arch
	arch=$(dpkg --print-architecture)
	local deb_url=""
	local deb_file="/tmp/wkhtmltox.deb"

	case "$arch" in
		amd64)
			deb_url="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb"
			;;
		arm64)
			deb_url="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_arm64.deb"
			;;
		*)
			log_warn "Unknown architecture: $arch - falling back to apt wkhtmltopdf (may not have patched qt)"
			safe_apt_install wkhtmltopdf || true
			return 0
			;;
	esac

	log_info "Downloading wkhtmltopdf for $arch..."
	curl -fsSL -o "$deb_file" "$deb_url" || {
		log_warn "Failed to download wkhtmltopdf - falling back to apt"
		safe_apt_install wkhtmltopdf || true
		rm -f "$deb_file"
		return 0
	}

	log_info "Installing wkhtmltopdf..."
	sudo dpkg -i "$deb_file" 2>/dev/null || {
		log_info "Resolving dependencies..."
		sudo apt-get -f install -y
		sudo dpkg -i "$deb_file"
	}
	rm -f "$deb_file"

	if command_exists wkhtmltopdf; then
		log_success "wkhtmltopdf $(wkhtmltopdf --version 2>&1 | head -1)"
	else
		log_warn "wkhtmltopdf installation failed - PDF generation may not work"
	fi
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

	local required_version
	required_version="$(_required_mariadb_version)"

	local need_install=false
	local current_ver=""
	if ! command_exists mariadb; then
		need_install=true
	else
		current_ver="$(_mariadb_server_version)"
		if [ -z "$current_ver" ] || version_lt "$current_ver" "$required_version"; then
			log_info "MariaDB ${current_ver:-unknown} found, but $required_version+ is required for Frappe v$FRAPPE_VER"
			need_install=true
		else
			log_success "MariaDB $current_ver meets requirement ($required_version+)"
		fi
	fi

	if [ "$need_install" = true ]; then
		if _distro_mariadb_is_sufficient "$required_version"; then
			log_info "Installing MariaDB from Ubuntu packages"
		else
			_add_mariadb_repo "$required_version" || {
				log_warn "MariaDB repo setup failed, using the distro package"
			}
		fi
		safe_apt_install mariadb-server mariadb-client
	fi

	sudo systemctl enable mariadb 2>/dev/null || true
	sudo systemctl start mariadb 2>/dev/null || true

	current_ver="$(_mariadb_server_version)"
	if [ -z "$current_ver" ] || version_lt "$current_ver" "$required_version"; then
		log_error "MariaDB ${current_ver:-not installed} is older than $required_version required for Frappe v$FRAPPE_VER"
		exit 1
	fi
	log_success "MariaDB $current_ver is installed"
}

_distro_mariadb_is_sufficient() {
	local required="$1"
	local shipped
	. /etc/os-release 2>/dev/null || true
	shipped="$(distro_mariadb_version "${VERSION_ID:-}")"
	[ -n "$shipped" ] || return 1
	version_lt "$shipped" "$required" && return 1
	log_info "Ubuntu ${VERSION_ID} ships MariaDB $shipped, which meets $required+."
	return 0
}

_required_mariadb_version() {
	# Matches current Frappe install docs: v15 needs 10.6+, v16 needs 11.8.
	if [ "$FRAPPE_VER" = "16" ]; then
		echo "11.8"
	else
		echo "10.6"
	fi
}

_mariadb_server_version() {
	mariadb_version_from_text "$(mariadb --version 2>/dev/null || true)"
}

_add_mariadb_repo() {
	local version="$1"
	log_info "Adding MariaDB $version repository..."

	. /etc/os-release 2>/dev/null || true
	local codename="${VERSION_CODENAME:-}"

	if [ -z "$codename" ]; then
		case "${VERSION_ID:-}" in
			20.04) codename="focal" ;;
			22.04) codename="jammy" ;;
			24.04) codename="noble" ;;
			26.04) log_info "Ubuntu 26.04 uses its own MariaDB packages"; return 1 ;;
			*) log_warn "Unknown Ubuntu version"; return 1 ;;
		esac
	fi

	sudo apt-get install -y apt-transport-https curl gnupg 2>/dev/null || true

	local keyring="/etc/apt/keyrings/mariadb.gpg"
	local key_tmp="/tmp/mariadb-release-key.pgp"
	sudo mkdir -p /etc/apt/keyrings
	curl -fsSL "https://mariadb.org/mariadb_release_signing_key.pgp" -o "$key_tmp" || {
		log_warn "Failed to download MariaDB GPG key"
		return 1
	}
	sudo rm -f "$keyring"
	sudo gpg --batch --yes --dearmor -o "$keyring" "$key_tmp" || {
		log_warn "Failed to add MariaDB GPG key"
		rm -f "$key_tmp"
		return 1
	}
	rm -f "$key_tmp"

	local repo_base
	repo_base="$(_mariadb_repo_base "$version" "$codename")" || {
		log_warn "No MariaDB $version repository for Ubuntu $codename"
		return 1
	}

	local repo_line="deb [signed-by=/etc/apt/keyrings/mariadb.gpg] ${repo_base} ${codename} main"
	echo "$repo_line" | sudo tee /etc/apt/sources.list.d/mariadb.list > /dev/null

	sudo apt-get update -y || {
		log_warn "Failed to update after adding MariaDB repo"
		sudo rm -f /etc/apt/sources.list.d/mariadb.list
		return 1
	}

	log_success "MariaDB $version repository added"
}

_mariadb_repo_base() {
	local version="$1"
	local codename="$2"
	local live="https://dlm.mariadb.com/repo/mariadb-server/${version}/repo/ubuntu"
	local patch archived

	if curl -fsI "${live}/dists/${codename}/Release" >/dev/null; then
		printf '%s\n' "$live"
		return 0
	fi

	# The live 11.8 mirror has no Ubuntu 20.04 (focal) suite. The archive still does.
	for patch in 11.8.8 11.8.7 11.8.6 11.8.5 11.8.3; do
		case "$patch" in
			"${version}".*) ;;
			*) continue ;;
		esac
		archived="https://archive.mariadb.org/mariadb-${patch}/repo/ubuntu"
		if curl -fsI "${archived}/dists/${codename}/Release" >/dev/null; then
			log_info "Using MariaDB archive $patch for Ubuntu $codename" >&2
			printf '%s\n' "$archived"
			return 0
		fi
	done
	return 1
}
