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
	log_info "Installing Frappe Bench ..."

	if [ -L /usr/local/bin/bench ] || [ -x /usr/local/bin/bench ]; then
		if /usr/local/bin/bench --version &>/dev/null; then
			log_success "bench already at /usr/local/bin/bench: $(/usr/local/bin/bench --version)"
			return 0
		fi
		sudo rm -f /usr/local/bin/bench
	fi

	local user_bench=""
	if [ -x "/home/$FRAPPE_USER/.local/bin/bench" ]; then
		user_bench="/home/$FRAPPE_USER/.local/bin/bench"
		log_info "Found existing user-local bench at $user_bench"
	fi

	if [ -z "$user_bench" ]; then
		if ! command_exists pipx; then
			sudo apt-get install -y pipx 2>/dev/null || sudo pip3 install --break-system-packages pipx
		fi

		log_info "Installing frappe-bench via pipx (system-wide to /opt/pipx)..."
		sudo PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install frappe-bench 2>/dev/null || {
			log_warn "System pipx install failed, installing as $FRAPPE_USER"
			sudo -u "$FRAPPE_USER" -H bash -c 'export PATH=$HOME/.local/bin:$PATH; pipx install frappe-bench'
			user_bench="/home/$FRAPPE_USER/.local/bin/bench"
		}
	fi

	if [ ! -L /usr/local/bin/bench ] && [ ! -x /usr/local/bin/bench ]; then
		if [ -n "$user_bench" ] && [ -x "$user_bench" ]; then
			log_info "Linking $user_bench → /usr/local/bin/bench"
			sudo ln -sf "$user_bench" /usr/local/bin/bench
		fi
	fi

	if ! /usr/local/bin/bench --version &>/dev/null && ! sudo /usr/local/bin/bench --version &>/dev/null; then
		log_error "bench global setup failed - /usr/local/bin/bench is not working"
		return 1
	fi

	log_success "bench available at /usr/local/bin/bench (works with sudo): $(/usr/local/bin/bench --version 2>/dev/null || sudo /usr/local/bin/bench --version)"
}

ensure_bench_global() {
	if [ -x /usr/local/bin/bench ] && /usr/local/bin/bench --version &>/dev/null; then
		return 0
	fi
	local user_bench
	user_bench=$(sudo -u "$FRAPPE_USER" -H bash -c 'export PATH=$HOME/.local/bin:/usr/local/bin:$PATH; command -v bench' 2>/dev/null || echo "")
	if [ -n "$user_bench" ] && [ -x "$user_bench" ]; then
		log_info "Creating /usr/local/bin/bench → $user_bench"
		sudo ln -sf "$user_bench" /usr/local/bin/bench
		return 0
	fi
	log_error "bench binary not found anywhere"
	return 1
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

wait_for_bench_services() {
	local bench_path="$1"
	local max_wait="${2:-120}"
	local config_file="$bench_path/sites/common_site_config.json"

	log_info "Waiting for bench services to be ready (max ${max_wait}s)..."

	local elapsed=0
	while [ $elapsed -lt $max_wait ]; do
		if [ -f "$config_file" ]; then
			local queue_port cache_port socketio_port
			queue_port=$(grep -oP '"redis_queue":\s*"redis://[^:]+:\K[0-9]+' "$config_file" 2>/dev/null || echo "")
			cache_port=$(grep -oP '"redis_cache":\s*"redis://[^:]+:\K[0-9]+' "$config_file" 2>/dev/null || echo "")
			socketio_port=$(grep -oP '"socketio_port":\s*\K[0-9]+' "$config_file" 2>/dev/null || echo "9000")

			local ready=0
			[ -n "$queue_port" ] && redis-cli -p "$queue_port" ping &>/dev/null && ready=$((ready + 1))
			[ -n "$cache_port" ] && redis-cli -p "$cache_port" ping &>/dev/null && ready=$((ready + 1))

			if [ $ready -ge 2 ]; then
				log_success "Bench Redis services ready (queue:$queue_port, cache:$cache_port)"
				return 0
			fi
		fi

		sleep 2
		elapsed=$((elapsed + 2))
		[ $((elapsed % 10)) -eq 0 ] && log_info "Still waiting... ${elapsed}s elapsed"
	done

	log_warn "Bench services not fully ready after ${max_wait}s"
	return 1
}

wait_for_bench_redis() {
	local bench_path="$1"
	local max_wait="${2:-60}"
	local config_file="$bench_path/sites/common_site_config.json"

	log_info "Waiting for bench Redis instances (max ${max_wait}s)..."

	if [ ! -f "$config_file" ]; then
		log_error "Config file not found: $config_file"
		return 1
	fi

	local queue_port cache_port
	queue_port=$(grep -oP '"redis_queue":\s*"redis://[^:]+:\K[0-9]+' "$config_file" 2>/dev/null || echo "11000")
	cache_port=$(grep -oP '"redis_cache":\s*"redis://[^:]+:\K[0-9]+' "$config_file" 2>/dev/null || echo "13000")

	log_info "Redis queue port: $queue_port, cache port: $cache_port"

	local elapsed=0
	while [ $elapsed -lt $max_wait ]; do
		local queue_ok=false cache_ok=false

		if redis-cli -p "$queue_port" ping &>/dev/null; then
			queue_ok=true
		fi
		if redis-cli -p "$cache_port" ping &>/dev/null; then
			cache_ok=true
		fi

		if [ "$queue_ok" = true ] && [ "$cache_ok" = true ]; then
			log_success "Redis ready - queue:$queue_port cache:$cache_port"
			return 0
		fi

		sleep 2
		elapsed=$((elapsed + 2))

		if [ $((elapsed % 10)) -eq 0 ]; then
			log_info "Waiting for Redis... ${elapsed}s (queue:$queue_ok cache:$cache_ok)"
		fi
	done

	log_error "Redis not ready after ${max_wait}s"
	log_info "Queue ($queue_port): $(redis-cli -p "$queue_port" ping 2>&1 || echo 'FAILED')"
	log_info "Cache ($cache_port): $(redis-cli -p "$cache_port" ping 2>&1 || echo 'FAILED')"
	return 1
}

wait_for_supervisor_services() {
	local max_wait="${1:-60}"
	local elapsed=0

	log_info "Checking supervisor services (max ${max_wait}s)..."

	sudo systemctl restart supervisor 2>/dev/null || true
	sleep 2
	sudo supervisorctl reread 2>/dev/null || true
	sudo supervisorctl update 2>/dev/null || true

	while [ $elapsed -lt $max_wait ]; do
		local output
		output=$(sudo supervisorctl status 2>&1 || echo "")
		
		if [ -z "$output" ]; then
			log_info "No supervisor processes found yet... ${elapsed}s"
			sleep 3
			elapsed=$((elapsed + 3))
			continue
		fi

		local total running
		total=$(echo "$output" | wc -l)
		running=$(echo "$output" | grep -c 'RUNNING' || echo "0")

		if [ "$running" -eq "$total" ] && [ "$total" -gt 0 ]; then
			log_success "All $running supervisor services running"
			return 0
		fi

		log_info "Services: $running/$total running... ${elapsed}s"
		sleep 3
		elapsed=$((elapsed + 3))
	done

	log_warn "Timeout after ${max_wait}s. Current status:"
	sudo supervisorctl status 2>/dev/null || true
	return 0
}

wait_for_web_ready() {
	local url="${1:-http://localhost:8000}"
	local max_wait="${2:-60}"
	local elapsed=0

	log_info "Waiting for web server at $url..."

	while [ $elapsed -lt $max_wait ]; do
		if curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null | grep -qE '^(200|302|301)$'; then
			log_success "Web server responding at $url"
			return 0
		fi
		sleep 2
		elapsed=$((elapsed + 2))
	done

	log_warn "Web server not responding after ${max_wait}s"
	return 1
}

stop_bench_processes() {
	local bench_path="$1"
	local user="$2"

	log_info "Stopping any existing bench processes..."
	pkill -f "bench start" 2>/dev/null || true
	pkill -f "honcho" 2>/dev/null || true

	local pids
	pids=$(pgrep -f "$bench_path" 2>/dev/null || true)
	if [ -n "$pids" ]; then
		log_info "Killing bench-related processes: $pids"
		kill $pids 2>/dev/null || true
		sleep 2
		kill -9 $pids 2>/dev/null || true
	fi
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

get_webserver_port() {
	local bench_path="$1"
	local config_file="$bench_path/sites/common_site_config.json"

	if [ -f "$config_file" ]; then
		local port
		port=$(grep -oP '"webserver_port":\s*\K[0-9]+' "$config_file" 2>/dev/null || echo "")
		if [ -n "$port" ]; then
			echo "$port"
			return
		fi
	fi

	local procfile="$bench_path/Procfile"
	if [ -f "$procfile" ]; then
		local port
		port=$(grep -oP 'serve --port\s+\K[0-9]+' "$procfile" 2>/dev/null || echo "")
		if [ -n "$port" ]; then
			echo "$port"
			return
		fi
	fi

	echo "8000"
}

get_socketio_port() {
	local bench_path="$1"
	local config_file="$bench_path/sites/common_site_config.json"

	if [ -f "$config_file" ]; then
		local port
		port=$(grep -oP '"socketio_port":\s*\K[0-9]+' "$config_file" 2>/dev/null || echo "")
		if [ -n "$port" ]; then
			echo "$port"
			return
		fi
	fi
	echo "9000"
}
