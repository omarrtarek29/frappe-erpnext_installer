#!/usr/bin/env bash
# Production: setup production, ensure services, optionally install ERPNext, SSL

setup_production() {
	log_info "Setting up production..."

	run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench --site '$SITE_NAME' enable-scheduler"
	run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench --site '$SITE_NAME' set-maintenance-mode off"
	
	run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench setup nginx --yes"
	sudo -u "$FRAPPE_USER" -H bash -c "$(get_bench_path_export); cd '$BENCH_PATH' && sudo bench setup production '$FRAPPE_USER' --yes"

	local redis_port
	redis_port=$(get_redis_queue_port "$BENCH_PATH")
	wait_for_redis "$redis_port" 15 || log_warn "Redis may not be ready - continuing anyway"

	if [ "${INSTALL_ERPNEXT:-yes}" = "yes" ]; then
		log_info "Installing ERPNext on site..."
		run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench --site '$SITE_NAME' install-app erpnext"
		log_success "ERPNext installed"
	else
		log_info "Skipping ERPNext installation (user chose not to install)."
	fi

	log_info "Installing SSL certificate..."
	sudo snap install core 2>/dev/null || true
	sudo snap refresh core 2>/dev/null || true
	sudo snap install --classic certbot 2>/dev/null || true
	sudo ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true

	if sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email 2>/dev/null; then
		log_success "SSL certificate installed"
	else
		log_warn "SSL installation failed. Run: sudo certbot --nginx -d $DOMAIN"
	fi
}
