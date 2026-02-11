#!/usr/bin/env bash
# Production: setup production, ensure services, optionally install ERPNext, SSL

setup_production() {
	log_info "Setting up production..."

	cd "$BENCH_PATH"
	bench --site "$SITE_NAME" enable-scheduler
	bench --site "$SITE_NAME" set-maintenance-mode off
	sudo bench setup production "$FRAPPE_USER" --yes
	bench setup nginx --yes
	sudo bench setup production "$FRAPPE_USER" --yes
	# Ensure Redis Queue is up before attempting ERPNext installation
	log_info "Waiting for Redis Queue (port 11001) to be ready..."
	for i in {1..30}; do
		if redis-cli -p 11001 ping &>/dev/null; then
			log_success "Redis Queue is ready"
			break
		fi
		log_info "Waiting for Redis Queue... ($i/30)"
		sleep 2
	done

	if ! redis-cli -p 11001 ping &>/dev/null; then
		log_warn "Redis Queue on port 11001 is not responding. ERPNext installation may fail."
	fi

	if [ "${INSTALL_ERPNEXT:-yes}" = "yes" ]; then
		log_info "Installing ERPNext on site..."
		sudo -u "$FRAPPE_USER" -H bash <<ERPINSTALL
set -e
export PATH="\$HOME/.local/bin:\$PATH"
cd "$BENCH_PATH"
bench --site "$SITE_NAME" install-app erpnext

ERPINSTALL
		log_success "ERPNext installed"
	else
		log_info "Skipping ERPNext installation (user chose not to install)."
	fi

	# SSL setup (optional but recommended)
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
