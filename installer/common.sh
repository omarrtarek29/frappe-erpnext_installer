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

is_legacy_pipx_bench() {
	local bench_bin="${1:-/usr/local/bin/bench}"
	[ -e "$bench_bin" ] || return 1

	local resolved
	resolved=$(readlink -f "$bench_bin" 2>/dev/null || echo "$bench_bin")
	if [[ "$resolved" == *"/opt/pipx/"* ]] || [[ "$resolved" == *"/pipx/venvs/frappe-bench/"* ]]; then
		return 0
	fi

	if grep -q '/opt/pipx/venvs/frappe-bench' "$bench_bin" 2>/dev/null; then
		return 0
	fi

	return 1
}

_uninstall_legacy_pipx_bench() {
	log_info "Removing legacy pipx frappe-bench..."

	if command_exists pipx; then
		sudo PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx uninstall frappe-bench 2>/dev/null || true
		sudo -u "$FRAPPE_USER" -H pipx uninstall frappe-bench 2>/dev/null || true
	fi

	sudo rm -f /usr/local/bin/bench
}

install_bench_globally() {
	log_info "Installing Frappe Bench via uv..."

	if ! command_exists uv; then
		log_error "uv is required but not installed"
		return 1
	fi

	if is_legacy_pipx_bench /usr/local/bin/bench; then
		log_warn "Legacy pipx bench detected (Python 3.12) - migrating to uv frappe-bench"
		_uninstall_legacy_pipx_bench
	elif [ -x /usr/local/bin/bench ] && ! is_legacy_pipx_bench /usr/local/bin/bench; then
		local uv_bench
		uv_bench=$(sudo -u "$FRAPPE_USER" -H bash -c '
			export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"
			command -v bench
		' 2>/dev/null || echo "")
		if [ -n "$uv_bench" ] && ! is_legacy_pipx_bench "$uv_bench"; then
			sudo ln -sf "$uv_bench" /usr/local/bin/bench
			log_success "bench already available via uv: $(/usr/local/bin/bench --version)"
			return 0
		fi
	fi

	log_info "Installing frappe-bench via uv tool for $FRAPPE_USER..."
	sudo -u "$FRAPPE_USER" -H bash -c '
		export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"
		uv tool install frappe-bench --force
	' || {
		log_error "Failed to install frappe-bench via uv"
		return 1
	}

	local user_bench=""
	user_bench=$(sudo -u "$FRAPPE_USER" -H bash -c '
		export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"
		command -v bench
	' 2>/dev/null || echo "")

	if [ -z "$user_bench" ] || [ ! -x "$user_bench" ] || is_legacy_pipx_bench "$user_bench"; then
		log_error "uv frappe-bench not found after install"
		return 1
	fi

	log_info "Linking $user_bench → /usr/local/bin/bench"
	sudo ln -sf "$user_bench" /usr/local/bin/bench

	if is_legacy_pipx_bench /usr/local/bin/bench; then
		log_error "bench still points to legacy pipx after migration"
		return 1
	fi

	if ! /usr/local/bin/bench --version &>/dev/null; then
		log_error "bench global setup failed - /usr/local/bin/bench is not working"
		return 1
	fi

	log_success "bench available at /usr/local/bin/bench: $(/usr/local/bin/bench --version)"
}

ensure_bench_global() {
	if is_legacy_pipx_bench /usr/local/bin/bench; then
		log_warn "Legacy pipx bench detected - migrating to uv frappe-bench"
		install_bench_globally || return 1
		return 0
	fi

	if [ -x /usr/local/bin/bench ] && /usr/local/bin/bench --version &>/dev/null; then
		return 0
	fi

	install_bench_globally || return 1
}

run_as_frappe_user() {
	local user="$1"
	shift
	sudo -u "$user" -H bash -c "
		export PATH=\"/usr/local/bin:/usr/bin:/bin\"
		export HOME=\"/home/$user\"
		export NVM_DIR=\"\$HOME/.nvm\"
		[ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
		$*
	"
}

remove_duplicate_bench_symlinks() {
	local conf_dir link target link_name expected="${BENCH_NAME}.conf"

	for conf_dir in /etc/nginx/conf.d /etc/supervisor/conf.d; do
		[ -d "$conf_dir" ] || continue
		for link in "$conf_dir"/*.conf; do
			[ -L "$link" ] || continue
			link_name=$(basename "$link")
			target=$(readlink -f "$link" 2>/dev/null || readlink "$link" 2>/dev/null || echo "")
			[[ "$target" == "$BENCH_PATH/config/"* ]] || continue
			[ "$link_name" = "$expected" ] && continue
			log_warn "Removing mislinked symlink for this bench: $link -> $target (should be ${expected})"
			sudo rm -f "$link"
		done
	done
}

link_bench_supervisor_config() {
	local link="/etc/supervisor/conf.d/${BENCH_NAME}.conf"
	local target="$BENCH_PATH/config/supervisor.conf"

	if [ ! -f "$target" ]; then
		log_warn "Missing $target"
		return 1
	fi

	local current
	current=$(readlink -f "$link" 2>/dev/null || echo "")
	if [ "$current" = "$(readlink -f "$target")" ]; then
		log_success "Supervisor linked: ${BENCH_NAME}.conf"
		return 0
	fi

	log_info "Linking supervisor: ${BENCH_NAME}.conf -> $target"
	sudo ln -sf "$target" "$link"
}

link_bench_nginx_config() {
	local link="/etc/nginx/conf.d/${BENCH_NAME}.conf"
	local target="$BENCH_PATH/config/nginx.conf"

	if [ ! -f "$target" ]; then
		log_warn "Missing $target"
		return 1
	fi

	local current
	current=$(readlink -f "$link" 2>/dev/null || echo "")
	if [ "$current" = "$(readlink -f "$target")" ]; then
		log_success "Nginx linked: ${BENCH_NAME}.conf"
		return 0
	fi

	log_info "Linking nginx: ${BENCH_NAME}.conf -> $target"
	sudo ln -sf "$target" "$link"
}

ensure_bench_service_links() {
	link_bench_supervisor_config
	link_bench_nginx_config
}

restore_other_bench_symlinks() {
	local other_bench other_name conf_file link_path target

	for other_bench in /home/"$FRAPPE_USER"/*/config/nginx.conf; do
		[ -f "$other_bench" ] || continue
		other_name=$(basename "$(dirname "$(dirname "$other_bench")")")
		[ "$other_name" = "$BENCH_NAME" ] && continue

		conf_file="/home/$FRAPPE_USER/$other_name/config/nginx.conf"
		link_path="/etc/nginx/conf.d/${other_name}.conf"
		target=$(readlink -f "$link_path" 2>/dev/null || echo "")
		if [ -n "$target" ] && [[ "$target" == "$BENCH_PATH/config/"* ]]; then
			log_warn "Restoring $other_name nginx symlink (was incorrectly pointing to $BENCH_NAME)"
			sudo ln -sf "$conf_file" "$link_path"
		fi

		conf_file="/home/$FRAPPE_USER/$other_name/config/supervisor.conf"
		link_path="/etc/supervisor/conf.d/${other_name}.conf"
		target=$(readlink -f "$link_path" 2>/dev/null || echo "")
		if [ -n "$target" ] && [[ "$target" == "$BENCH_PATH/config/"* ]]; then
			log_warn "Restoring $other_name supervisor symlink (was incorrectly pointing to $BENCH_NAME)"
			sudo ln -sf "$conf_file" "$link_path"
		fi
	done
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

	while [ $elapsed -lt $max_wait ]; do
		local output
		output=$(sudo supervisorctl status 2>&1 || echo "")

		if echo "$output" | grep -qE 'unix:///var/run/supervisor.sock no such file|refused connection'; then
			log_info "Supervisor socket not ready... ${elapsed}s"
			sleep 3
			elapsed=$((elapsed + 3))
			continue
		fi

		if [ -z "$output" ] || echo "$output" | grep -q 'ERROR (no such process)'; then
			log_info "No supervisor processes found yet... ${elapsed}s"
			sleep 3
			elapsed=$((elapsed + 3))
			continue
		fi

		local total running
		total=$(echo "$output" | grep -cE 'RUNNING|STARTING|STOPPED|FATAL|BACKOFF|EXITED' || echo "0")
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
	return 1
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
	pkill -f "bench serve" 2>/dev/null || true
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

free_port() {
	local port="$1"
	[ -n "$port" ] || return 0
	if command_exists fuser; then
		sudo fuser -k "${port}/tcp" 2>/dev/null || true
	fi
}

free_bench_ports() {
	local bench_path="$1"
	local web_port socketio_port queue_port cache_port file_port

	web_port=$(get_webserver_port "$bench_path")
	socketio_port=$(get_socketio_port "$bench_path")
	queue_port=$(get_redis_queue_port "$bench_path")
	cache_port=$(get_redis_cache_port "$bench_path")
	file_port=$(grep -oP '"file_watcher_port":\s*\K[0-9]+' "$bench_path/sites/common_site_config.json" 2>/dev/null || echo "")

	log_info "Freeing bench ports (web:$web_port redis:$queue_port/$cache_port socketio:$socketio_port)..."

	for port in "$web_port" "$socketio_port" "$queue_port" "$cache_port" "$file_port"; do
		free_port "$port"
	done
	sleep 1
}

stop_supervisor_bench() {
	local bench_name="$1"
	[ -n "$bench_name" ] || return 0

	if ! command_exists supervisorctl; then
		return 0
	fi

	log_info "Stopping supervisor processes for $bench_name..."
	sudo supervisorctl stop "${bench_name}-web:" 2>/dev/null || true
	sudo supervisorctl stop "${bench_name}-workers:" 2>/dev/null || true
	sudo supervisorctl stop "${bench_name}-redis:" 2>/dev/null || true
	sudo supervisorctl stop "${bench_name}-processes:" 2>/dev/null || true
}

disable_dev_systemd_service() {
	local service_name="bench-$BENCH_NAME"
	if systemctl list-unit-files "$service_name.service" &>/dev/null; then
		log_info "Disabling systemd dev service: $service_name"
		sudo systemctl stop "$service_name" 2>/dev/null || true
		sudo systemctl disable "$service_name" 2>/dev/null || true
	fi
}

prepare_bench_logs() {
	run_as_frappe_user "$FRAPPE_USER" "mkdir -p '$BENCH_PATH/logs'"
	sudo chown -R "$FRAPPE_USER:$FRAPPE_USER" "$BENCH_PATH/logs"
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

get_redis_cache_port() {
	local bench_path="$1"
	local config_file="$bench_path/sites/common_site_config.json"

	if [ -f "$config_file" ]; then
		local port
		port=$(grep -oP '"redis_cache":\s*"redis://[^:]+:\K[0-9]+' "$config_file" 2>/dev/null || echo "")
		if [ -n "$port" ]; then
			echo "$port"
			return
		fi
	fi
	echo "13000"
}

configure_bench_redis() {
	local queue_conf="$BENCH_PATH/config/redis_queue.conf"
	local cache_conf="$BENCH_PATH/config/redis_cache.conf"
	local pids_dir="$BENCH_PATH/config/pids"

	run_as_frappe_user "$FRAPPE_USER" "mkdir -p '$pids_dir'"

	if [ -f "$queue_conf" ] && ! grep -qE '^save\s+""' "$queue_conf"; then
		log_info "Disabling RDB snapshots on bench queue Redis..."
		echo 'save ""' >> "$queue_conf"
	fi

	if [ -f "$cache_conf" ] && ! grep -qE '^save\s+""' "$cache_conf"; then
		echo 'save ""' >> "$cache_conf"
	fi
}

prepare_bench_redis_runtime() {
	local queue_port cache_port
	queue_port=$(get_redis_queue_port "$BENCH_PATH")
	cache_port=$(get_redis_cache_port "$BENCH_PATH")

	for port in "$queue_port" "$cache_port"; do
		redis-cli -p "$port" CONFIG SET stop-writes-on-bgsave-error no 2>/dev/null || true
		redis-cli -p "$port" CONFIG SET save "" 2>/dev/null || true
	done
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
