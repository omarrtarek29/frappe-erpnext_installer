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

	ensure_nginx_main_log_format
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

ensure_nginx_main_log_format() {
	if sudo grep -qE '^[[:space:]]*log_format[[:space:]]+main[[:space:]]' /etc/nginx/nginx.conf; then
		return 0
	fi

	log_info "Adding nginx log_format main so the bench config can load"
	local snippet
	snippet="$(mktemp)"
	cat > "$snippet" <<'EOF'
	log_format main '$remote_addr - $remote_user [$time_local] "$request" '
	                '$status $body_bytes_sent "$http_referer" '
	                '"$http_user_agent" "$http_x_forwarded_for"';
EOF
	sudo python3 - "$snippet" <<'PY'
import pathlib, sys
snippet = pathlib.Path(sys.argv[1]).read_text()
conf_path = pathlib.Path("/etc/nginx/nginx.conf")
conf = conf_path.read_text()
needle = "access_log /var/log/nginx/access.log;"
if needle not in conf:
    raise SystemExit("nginx.conf has no access_log line to anchor log_format main")
conf_path.write_text(conf.replace(needle, snippet.rstrip() + "\n\n\t" + needle, 1))
PY
	rm -f "$snippet"
}

setup_ssl_certificate() {
	log_info "Setting up SSL certificate..."
	ensure_nginx_main_log_format
	if ! sudo nginx -t; then
		log_warn "nginx -t failed, so Certbot cannot install a certificate"
		return 1
	fi

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

	local certbot_status=0
	if [ -n "${SSL_EMAIL:-}" ]; then
		sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$SSL_EMAIL" || certbot_status=$?
	else
		log_warn "No SSL_EMAIL set - certificate renewal notifications disabled"
		sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email || certbot_status=$?
	fi

	if [ "$certbot_status" -eq 0 ]; then
		log_success "SSL certificate installed for $DOMAIN"
		sudo systemctl reload nginx 2>/dev/null || true
	else
		log_warn "SSL installation failed. Manual setup: sudo certbot --nginx -d $DOMAIN"
	fi
}
