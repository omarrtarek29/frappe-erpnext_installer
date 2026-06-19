#!/usr/bin/env bash

setup_production() {
	log_info "Setting up production mode..."

	ensure_bench_global || {
		log_error "Cannot proceed - bench is not accessible system-wide"
		exit 1
	}

	if [ "${INSTALL_ERPNEXT:-yes}" = "yes" ]; then
		log_info "Installing ERPNext on site (before production setup)..."
		run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench --site '$SITE_NAME' install-app erpnext"
		log_success "ERPNext installed"
	else
		log_info "Skipping ERPNext installation"
	fi

	run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench --site '$SITE_NAME' enable-scheduler"
	run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench --site '$SITE_NAME' set-maintenance-mode off"

	log_info "Generating nginx config..."
	run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench setup nginx --yes"

	log_info "Setting up production (nginx + supervisor)..."
	sudo bash -c "cd '$BENCH_PATH' && /usr/local/bin/bench setup production '$FRAPPE_USER' --yes"

	log_info "Reloading services..."
	sudo systemctl daemon-reload
	sudo systemctl restart nginx 2>/dev/null || true
	sudo supervisorctl reread 2>/dev/null || true
	sudo supervisorctl update 2>/dev/null || true
	sudo supervisorctl restart all 2>/dev/null || true

	wait_for_supervisor_services 90 || log_warn "Some supervisor services may not be running"

	setup_ssl_certificate

	log_success "Production mode configured"
}

setup_ssl_certificate() {
	log_info "Setting up SSL certificate..."

	if ! command_exists certbot; then
		sudo snap install core 2>/dev/null || true
		sudo snap refresh core 2>/dev/null || true
		sudo snap install --classic certbot 2>/dev/null || {
			sudo apt-get install -y certbot python3-certbot-nginx 2>/dev/null || true
		}
		sudo ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true
	fi

	if ! command_exists certbot; then
		log_warn "Certbot not installed. Install manually: sudo snap install --classic certbot"
		return 1
	fi

	local email_flag=""
	if [ -n "${SSL_EMAIL:-}" ]; then
		email_flag="-m $SSL_EMAIL"
	else
		email_flag="--register-unsafely-without-email"
		log_warn "No SSL_EMAIL set - certificate renewal notifications disabled"
	fi

	if sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos $email_flag 2>/dev/null; then
		log_success "SSL certificate installed for $DOMAIN"
		sudo systemctl reload nginx 2>/dev/null || true
	else
		log_warn "SSL installation failed. Manual setup: sudo certbot --nginx -d $DOMAIN"
	fi
}
