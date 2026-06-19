#!/usr/bin/env bash

setup_production() {
	log_info "Setting up production mode..."

	ensure_bench_global || {
		log_error "Cannot proceed - bench is not accessible system-wide"
		exit 1
	}

	log_info "Installing ansible (required by bench)..."
	sudo apt-get install -y ansible 2>/dev/null || sudo pip3 install ansible

	log_info "Setting up production..."
	cd "$BENCH_PATH"
	sudo bench setup production "$FRAPPE_USER" --yes

	log_info "Restarting supervisor..."
	sudo systemctl restart supervisor
	sleep 3
	sudo supervisorctl reread
	sudo supervisorctl update
	sudo supervisorctl restart all 2>/dev/null || true

	wait_for_supervisor_services 120 || {
		log_warn "Some supervisor services may not be running"
		sudo supervisorctl status
	}

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
