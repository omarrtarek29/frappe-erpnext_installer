#!/usr/bin/env bash
# Common logging and helper functions for Frappe/ERPNext installer

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

get_bench_path_export() {
	echo 'export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"'
}

setup_user_profile() {
	local user="$1"
	local home="/home/$user"
	local profile_line='export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"'
	
	for rc_file in "$home/.bashrc" "$home/.profile"; do
		if [ -f "$rc_file" ]; then
			if ! grep -qF '.local/bin' "$rc_file" 2>/dev/null; then
				echo "" | sudo tee -a "$rc_file" >/dev/null
				echo "# Frappe bench PATH" | sudo tee -a "$rc_file" >/dev/null
				echo "$profile_line" | sudo tee -a "$rc_file" >/dev/null
				sudo chown "$user:$user" "$rc_file"
			fi
		fi
	done
}

run_as_frappe_user() {
	local user="$1"
	shift
	sudo -u "$user" -H bash -c "$(get_bench_path_export); $*"
}

wait_for_redis() {
	local port="${1:-11000}"
	local max_attempts="${2:-15}"
	local wait_time=1
	
	log_info "Waiting for Redis on port $port..."
	for ((i=1; i<=max_attempts; i++)); do
		if redis-cli -p "$port" ping &>/dev/null; then
			log_success "Redis on port $port is ready"
			return 0
		fi
		log_info "Attempt $i/$max_attempts - waiting ${wait_time}s..."
		sleep "$wait_time"
		# Exponential backoff: 1, 2, 4, 4, 4... (capped at 4s)
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
