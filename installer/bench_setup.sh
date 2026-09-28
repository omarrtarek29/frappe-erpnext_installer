#!/usr/bin/env bash

install_bench_and_site() {
	log_info "Initializing Bench..."

	_remove_incomplete_bench
	assert_install_disk_space

	if [ -d "$BENCH_PATH" ]; then
		if [ ! -x "$BENCH_PATH/env/bin/python" ]; then
			log_error "$BENCH_PATH exists but is not a bench (missing env/bin/python)"
			exit 1
		fi
		if [ -d "$BENCH_PATH/sites/$SITE_NAME" ] && [ "${FORCE_SITE:-no}" != "yes" ]; then
			log_error "Site $SITE_NAME already exists at $BENCH_PATH"
			log_error "Choose another SITE_NAME, or set FORCE_SITE=yes to recreate it"
			exit 1
		fi
		log_info "Using existing bench at $BENCH_PATH"
	else
		log_info "Creating bench with Python: $PYTHON_BIN"
		_init_new_bench || exit 1
	fi

	_create_or_replace_site || exit 1
	_verify_bench_integrity
	configure_bench_redis

	log_success "Bench initialized with site $SITE_NAME"
}

_frappe_bash() {
	# Pass secrets in the environment so quotes and shell metacharacters stay intact.
	sudo -n -u "$FRAPPE_USER" -H env \
		HOME="/home/$FRAPPE_USER" \
		PATH="/usr/local/bin:/usr/bin:/bin" \
		ADMIN_PASS="$ADMIN_PASS" \
		MYSQL_ROOT_PASS="${MYSQL_ROOT_PASS:-}" \
		BENCH_PATH="$BENCH_PATH" \
		FRAPPE_HOME="$FRAPPE_HOME" \
		PYTHON_BIN="$PYTHON_BIN" \
		FRAPPE_BRANCH="$FRAPPE_BRANCH" \
		SITE_NAME="$SITE_NAME" \
		FORCE_SITE="${FORCE_SITE:-no}" \
		INSTALL_ERPNEXT="${INSTALL_ERPNEXT:-yes}" \
		bash -s
}

_remove_incomplete_bench() {
	[ -d "$BENCH_PATH" ] || return 0
	[ -f "$BENCH_PATH/sites/common_site_config.json" ] && return 0
	log_warn "Removing incomplete bench at $BENCH_PATH"
	rm -rf "$BENCH_PATH"
}

_init_new_bench() {
	if _frappe_bash <<'EOF'
set -e
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
cd "$FRAPPE_HOME"
# Answer the failure prompt so a full disk does not leave bench waiting on [y/N].
printf 'y\n' | bench init "$BENCH_PATH" --python "$PYTHON_BIN" --frappe-branch "$FRAPPE_BRANCH"
cd "$BENCH_PATH"
./env/bin/python -c 'import frappe'
EOF
	then
		return 0
	fi
	_remove_incomplete_bench
	return 1
}

_create_or_replace_site() {
	_frappe_bash <<'EOF'
set -e
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
cd "$BENCH_PATH"

if [ "$INSTALL_ERPNEXT" = "yes" ] && [ ! -d apps/erpnext ]; then
	bench get-app erpnext --branch "$FRAPPE_BRANCH"
fi

args=(new-site "$SITE_NAME" --admin-password "$ADMIN_PASS")
if [ "$FORCE_SITE" = "yes" ]; then
	args+=(--force)
fi
if [ -n "$MYSQL_ROOT_PASS" ]; then
	args+=(--mariadb-root-password "$MYSQL_ROOT_PASS")
fi

if [ ! -d "sites/$SITE_NAME" ] || [ "$FORCE_SITE" = "yes" ]; then
	bench "${args[@]}"
fi
bench use "$SITE_NAME"
EOF
}

_verify_bench_integrity() {
	log_info "Verifying bench integrity..."

	if [ ! -d "$BENCH_PATH/env" ]; then
		log_error "Bench env directory missing"
		exit 1
	fi

	if [ ! -x "$BENCH_PATH/env/bin/python" ]; then
		log_error "Bench Python not found"
		exit 1
	fi

	local import_check
	import_check=$(sudo -u "$FRAPPE_USER" -H bash -c "
		cd '$BENCH_PATH'
		./env/bin/python -c 'import frappe; print(frappe.__version__)' 2>&1
	" || echo "FAILED")

	if [ "$import_check" = "FAILED" ] || [ -z "$import_check" ]; then
		log_error "Frappe module not importable - bench may be corrupted"
		log_error "Delete $BENCH_PATH and retry"
		exit 1
	fi

	log_success "Bench integrity verified - frappe $import_check"
}

install_apps_with_temp_redis() {
	if [ "${INSTALL_ERPNEXT:-yes}" != "yes" ]; then
		log_info "Skipping ERPNext installation"
		return 0
	fi

	log_info "Starting temporary bench for app installation..."

	configure_bench_redis
	stop_bench_processes "$BENCH_PATH" "$FRAPPE_USER"
	run_as_frappe_user "$FRAPPE_USER" "mkdir -p '$BENCH_PATH/logs'"

	run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && nohup bench start > logs/temp-bench.log 2>&1 &"

	wait_for_bench_redis "$BENCH_PATH" 90 || {
		log_error "Redis not ready for app installation"
		sudo -u "$FRAPPE_USER" tail -n 50 "$BENCH_PATH/logs/temp-bench.log" 2>/dev/null || true
		stop_bench_processes "$BENCH_PATH" "$FRAPPE_USER"
		exit 1
	}

	prepare_bench_redis_runtime

	log_info "Installing ERPNext on site..."
	run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench --site '$SITE_NAME' install-app erpnext"
	run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench --site '$SITE_NAME' enable-scheduler"
	run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench --site '$SITE_NAME' set-maintenance-mode off"

	log_info "Stopping temporary bench..."
	stop_bench_processes "$BENCH_PATH" "$FRAPPE_USER"
	reset_bench_redis_runtime "$BENCH_PATH" "$BENCH_NAME"
	ensure_bench_ports_free "$BENCH_PATH" || exit 1

	log_success "ERPNext installed"
}
