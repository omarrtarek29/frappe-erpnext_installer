#!/usr/bin/env bash

log_info() {
	echo -e "\n\033[1;34m[INFO]\033[0m $1"
}

log_success() {
	echo -e "\033[1;32m[✓]\033[0m $1"
}

log_warn() {
	echo -e "\033[1;33m[WARN]\033[0m $1"
}

log_error() {
	echo -e "\033[1;31m[ERROR]\033[0m $1"
}

command_exists() {
	command -v "$1" &>/dev/null
}

safe_apt_install() {
	log_info "Installing: $*"
	sudo apt-get install -y "$@" || {
		log_warn "Fixing broken packages..."
		sudo apt-get -f install -y
		sudo dpkg --configure -a
		sudo apt-get install -y "$@"
	}
}

install_bench_globally() {
	log_info "Installing Frappe Bench globally to /usr/local/bin..."

	if [ -f "/home/$FRAPPE_USER/.local/bin/bench" ]; then
		log_info "Removing user-local bench installation..."
		sudo -u "$FRAPPE_USER" -H bash -c 'pipx uninstall frappe-bench 2>/dev/null || pip3 uninstall -y frappe-bench 2>/dev/null || true'
		sudo rm -f "/home/$FRAPPE_USER/.local/bin/bench"
	fi

	if [ -L /usr/local/bin/bench ] || [ -f /usr/local/bin/bench ]; then
		if /usr/local/bin/bench --version &>/dev/null; then
			log_success "bench already installed globally: $(/usr/local/bin/bench --version)"
			return 0
		fi
		sudo rm -f /usr/local/bin/bench
	fi

	if ! command_exists pipx; then
		sudo apt-get install -y pipx || sudo pip3 install --break-system-packages pipx
	fi

	sudo PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install frappe-bench || {
		log_warn "pipx install failed, falling back to pip"
		sudo pip3 install --break-system-packages frappe-bench
	}

	if ! /usr/local/bin/bench --version &>/dev/null; then
		log_error "Global bench installation failed"
		return 1
	fi

	log_success "bench installed globally: $(/usr/local/bin/bench --version)"
}

run_as_frappe_user() {
	local user="$1"
	shift
	sudo -u "$user" -H bash -c "export PATH=/usr/local/bin:/usr/bin:/bin; $*"
}

keep_sudo_alive() {
	log_info "Caching sudo credentials..."
	sudo -v

	(
		while true; do
			sudo -n true 2>/dev/null
			sleep 60
			kill -0 "$$" 2>/dev/null || exit
		done
	) &
	SUDO_KEEPALIVE_PID=$!
	export SUDO_KEEPALIVE_PID
}

stop_sudo_keepalive() {
	if [ -n "${SUDO_KEEPALIVE_PID:-}" ]; then
		kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
	fi
}

wait_for_redis() {
	local port="${1:-11000}"
	local max_attempts="${2:-15}"
	local wait_time=1

	log_info "Waiting for Redis on port $port..."
	for ((i = 1; i <= max_attempts; i++)); do
		if redis-cli -p "$port" ping &>/dev/null; then
			log_success "Redis on port $port is ready"
			return 0
		fi
		log_info "Attempt $i/$max_attempts - waiting ${wait_time}s..."
		sleep "$wait_time"
		[ "$wait_time" -lt 4 ] && wait_time=$((wait_time * 2))
	done

	log_warn "Redis on port $port not responding after $max_attempts attempts"
	return 1
}

get_redis_queue_port() {
	local bench_path="$1"
	local config_file="$bench_path/sites/common_site_config.json"

	if [ -f "$config_file" ]; then
		local port
		port=$(grep -oP '"redis_queue":\s*"redis://[^:]+:\K[0-9]+' "$config_file" 2>/dev/null || echo "")
		if [ -n "$port" ]; then
			echo "$port"
			return
		fi
	fi
	echo "11000"
}
