#!/usr/bin/env bash

configure_firewall() {
	if ! command_exists ufw; then
		log_info "UFW not installed - skipping firewall configuration"
		return 0
	fi

	log_info "Configuring UFW firewall..."

	sudo ufw allow 22/tcp comment 'SSH'

	if [ -n "$DOMAIN" ]; then
		sudo ufw allow 80/tcp comment 'HTTP'
		sudo ufw allow 443/tcp comment 'HTTPS'
	else
		local web_port socketio_port
		web_port=$(get_webserver_port "$BENCH_PATH")
		socketio_port=$(get_socketio_port "$BENCH_PATH")
		
		sudo ufw allow "$web_port/tcp" comment "Frappe Dev Server"
		sudo ufw allow "$socketio_port/tcp" comment "Frappe SocketIO"
		log_info "Opened ports: $web_port (web), $socketio_port (socketio)"
	fi

	sudo ufw --force enable
	log_success "Firewall configured"
	sudo ufw status verbose
}
