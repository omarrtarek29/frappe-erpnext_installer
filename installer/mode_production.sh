#!/usr/bin/env bash

_recover_supervisor() {
	log_warn "Supervisor services unhealthy - regenerating config..."
	prepare_bench_for_services
	_run_bench_cmd "bench setup supervisor --yes"
	setup_bench_redis_configs
	restore_other_bench_symlinks
	remove_duplicate_bench_symlinks
	ensure_bench_service_links
	start_bench_supervisor
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

	prepare_bench_for_services
	setup_bench_redis_configs
	start_bench_supervisor || {
		log_warn "Supervisor start failed - retrying recovery..."
		_recover_supervisor || {
			log_error "Supervisor services failed to start"
			sudo supervisorctl status 2>/dev/null || true
			exit 1
		}
	}

	if ! wait_for_supervisor_services 30; then
		log_warn "Supervisor services not healthy - retrying..."
		restart_bench_supervisor
		wait_for_supervisor_services 90 || {
			log_error "Supervisor services failed to start"
			sudo supervisorctl status 2>/dev/null || true
			exit 1
		}
	fi

	sudo nginx -t && sudo systemctl reload nginx

	local web_host="${DOMAIN:-$SITE_NAME}"
	wait_for_web_ready "http://127.0.0.1" 60 "$web_host" || \
		log_warn "Web server may not be responding for $web_host"

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
