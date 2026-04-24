#!/usr/bin/env bash
# Development: start bench, wait for Redis, optionally install ERPNext on site

setup_dev_mode() {
	log_info "Starting development mode..."

	run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && nohup bench start > bench.log 2>&1 &"
	log_info "Bench starting in background..."
	
	sleep 5

	local redis_port
	redis_port=$(get_redis_queue_port "$BENCH_PATH")
	wait_for_redis "$redis_port" 15 || log_warn "Redis may not be ready - continuing anyway"

	if [ "${INSTALL_ERPNEXT:-yes}" = "yes" ]; then
		log_info "Installing ERPNext on site..."
		run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench --site '$SITE_NAME' install-app erpnext"
		run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench --site '$SITE_NAME' enable-scheduler"
		run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench --site '$SITE_NAME' set-maintenance-mode off"
		log_success "ERPNext installation complete"
	else
		log_info "Skipping ERPNext installation (user chose not to install)."
	fi

	log_success "Development mode running"
}
