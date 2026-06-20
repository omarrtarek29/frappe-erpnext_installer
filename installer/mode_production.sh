#!/usr/bin/env bash

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
	_run_bench_cmd "bench setup supervisor --yes"
	restore_other_bench_symlinks
	remove_duplicate_bench_symlinks
	ensure_bench_service_links
	_reload_supervisor
}

setup_production() {
	log_info "Setting up production mode..."

	ensure_bench_global || {
		log_error "Cannot proceed - bench is not accessible system-wide"
		exit 1
	}

	cd "$BENCH_PATH"

	if [ -n "$DOMAIN" ]; then
		_run_bench_cmd "bench config dns_multitenant on"
		if [ "$DOMAIN" != "$SITE_NAME" ]; then
			_run_bench_cmd "bench setup add-domain '$DOMAIN' --site '$SITE_NAME'"
		fi
	fi

	# bench setup production creates ${BENCH_NAME}.conf symlinks itself.
	# Fix any cross-bench symlink damage from prior installs, then clean wrong names for this bench only.
	restore_other_bench_symlinks
	remove_duplicate_bench_symlinks
	sudo rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

	log_info "Running bench setup production..."
	cd "$BENCH_PATH"
	sudo env "PATH=$PATH" bench setup production "$FRAPPE_USER" --yes

	log_info "Generating supervisor and nginx configs..."
	_run_bench_cmd "bench setup supervisor --yes"
	_run_bench_cmd "bench setup nginx --yes"

	restore_other_bench_symlinks
	remove_duplicate_bench_symlinks
	ensure_bench_service_links
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

_run_bench_cmd() {
	local cmd="$1"
	sudo -u "$FRAPPE_USER" -H bash -c "
		export PATH=\"/usr/local/bin:/usr/bin:/bin\"
		export HOME=\"/home/$FRAPPE_USER\"
		export NVM_DIR=\"\$HOME/.nvm\"
		[ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
		cd '$BENCH_PATH'
		$cmd
	"
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
