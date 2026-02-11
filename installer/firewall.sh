#!/usr/bin/env bash
# UFW firewall configuration

configure_firewall() {
	if command_exists ufw; then
		log_info "Configuring firewall..."
		sudo ufw allow 22,80,443,8000/tcp
		sudo ufw --force enable
		log_success "Firewall configured"
	fi
}
