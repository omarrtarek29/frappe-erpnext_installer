#!/usr/bin/env bash

_link_bench_configs() {
	log_info "Linking bench configs to system paths..."

	if [ -f "$BENCH_PATH/config/supervisor.conf" ]; then
		sudo ln -sf "$BENCH_PATH/config/supervisor.conf" /etc/supervisor/conf.d/frappe-bench.conf
		log_success "Supervisor config linked"
	else
		log_warn "Missing $BENCH_PATH/config/supervisor.conf"
	fi

	if [ -f "$BENCH_PATH/config/nginx.conf" ]; then
		sudo ln -sf "$BENCH_PATH/config/nginx.conf" /etc/nginx/conf.d/frappe-bench.conf
		log_success "Nginx config linked"
	else
		log_warn "Missing $BENCH_PATH/config/nginx.conf"
	fi

	sudo rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
}

_reload_supervisor() {
	log_info "Reloading supervisor..."
	sudo systemctl enable supervisor 2>/dev/null || true
	sudo systemctl restart supervisor
	sleep 3
	sudo supervisorctl reread
	sudo supervisorctl update
	sudo supervisorctl restart all 2>/dev/null || true
}

_recover_supervisor() {
	log_warn "Supervisor has no bench processes - regenerating config..."
	run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench setup supervisor '$FRAPPE_USER' --yes"
	_link_bench_configs
	_reload_supervisor
}

setup_production() {
	log_info "Setting up production mode..."

	ensure_bench_global || {
		log_error "Cannot proceed - bench is not accessible system-wide"
		exit 1
	}

	log_info "Installing ansible (required by bench)..."
	sudo apt-get install -y ansible 2>/dev/null || sudo pip3 install ansible

	cd "$BENCH_PATH"

	if [ -n "$DOMAIN" ]; then
		run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench config dns_multitenant on"
		if [ "$DOMAIN" != "$SITE_NAME" ]; then
			run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench setup add-domain '$DOMAIN' --site '$SITE_NAME'"
		fi
	fi

	log_info "Setting up production (pass 1)..."
	sudo bench setup production "$FRAPPE_USER" --yes

	log_info "Generating supervisor config..."
	run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench setup supervisor '$FRAPPE_USER' --yes"

	log_info "Generating nginx config..."
	run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench setup nginx --yes"

	_link_bench_configs
	_reload_supervisor

	log_info "Setting up production (pass 2)..."
	sudo bench setup production "$FRAPPE_USER" --yes
	_link_bench_configs
	_reload_supervisor

	if ! wait_for_supervisor_services 30; then
		_recover_supervisor
		wait_for_supervisor_services 90 || {
			log_warn "Supervisor may not be fully ready"
			sudo supervisorctl status 2>/dev/null || true
		}
	fi

	sudo nginx -t && sudo systemctl reload nginx

	wait_for_web_ready "http://localhost:80" 60 || log_warn "Web server may not be responding on port 80"

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
