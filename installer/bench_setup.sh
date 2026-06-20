#!/usr/bin/env bash

install_bench_and_site() {
	log_info "Initializing Bench..."

	if [ -d "$BENCH_PATH" ]; then
		log_error "Bench directory already exists at $BENCH_PATH"
		log_error "Choose a different BENCH_NAME or remove the existing directory"
		exit 1
	fi

	local site_flags=""
	if [ "${FORCE_SITE:-no}" = "yes" ]; then
		site_flags="--force"
	fi

	local admin_pass_escaped
	admin_pass_escaped=$(printf '%s' "$ADMIN_PASS" | sed 's/[&/\]/\\&/g')
	local mysql_pass_escaped=""
	if [ -n "${MYSQL_ROOT_PASS:-}" ]; then
		mysql_pass_escaped=$(printf '%s' "$MYSQL_ROOT_PASS" | sed 's/[&/\]/\\&/g')
	fi

	log_info "Creating bench with Python: $PYTHON_BIN"

	sudo -u "$FRAPPE_USER" -H bash -c "
set -e
export PATH=\"/usr/local/bin:/usr/bin:/bin\"
export HOME=\"/home/$FRAPPE_USER\"
export NVM_DIR=\"\$HOME/.nvm\"
[ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
export ADMIN_PASS='$admin_pass_escaped'
export MYSQL_ROOT_PASS='$mysql_pass_escaped'

cd \"$FRAPPE_HOME\"

bench init \"$BENCH_PATH\" --python \"$PYTHON_BIN\" --frappe-branch \"$FRAPPE_BRANCH\"

cd \"$BENCH_PATH\"

# Verify frappe is importable
if ! ./env/bin/python -c 'import frappe' 2>/dev/null; then
    echo 'ERROR: frappe module not importable after bench init'
    exit 1
fi

if [ ! -d \"apps/erpnext\" ]; then
    bench get-app erpnext --branch \"$FRAPPE_BRANCH\"
else
    echo 'ERPNext app already present'
fi

if [ \"$FRAPPE_VER\" = \"15\" ]; then
    ./env/bin/pip install --upgrade pip
    ./env/bin/pip install 'setuptools>=58,<75'
fi

if [ ! -d \"sites/$SITE_NAME\" ] || [ \"${FORCE_SITE:-no}\" = \"yes\" ]; then
    if [ -n \"\$MYSQL_ROOT_PASS\" ]; then
        bench new-site \"$SITE_NAME\" $site_flags --admin-password \"\$ADMIN_PASS\" --mariadb-root-password \"\$MYSQL_ROOT_PASS\"
    else
        bench new-site \"$SITE_NAME\" $site_flags --admin-password \"\$ADMIN_PASS\"
    fi
fi

bench use \"$SITE_NAME\"
"

	_verify_bench_integrity
	configure_bench_redis

	log_success "Bench initialized with site $SITE_NAME"
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
