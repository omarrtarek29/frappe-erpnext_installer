#!/usr/bin/env bash

setup_dev_mode() {
	log_info "Setting up development mode..."

	stop_bench_processes "$BENCH_PATH" "$FRAPPE_USER"

	create_dev_systemd_service

	log_info "Starting bench service..."
	sudo systemctl daemon-reload
	sudo systemctl enable "bench-$BENCH_NAME" 2>/dev/null || true
	sudo systemctl start "bench-$BENCH_NAME"

	log_info "Waiting for Redis and services to be ready..."
	wait_for_bench_redis "$BENCH_PATH" 90 || {
		log_error "Redis services failed to start"
		sudo journalctl -u "bench-$BENCH_NAME" --no-pager -n 50
		exit 1
	}

	local web_port
	web_port=$(get_webserver_port "$BENCH_PATH")
	wait_for_web_ready "http://localhost:$web_port" 60 || log_warn "Web server may not be responding yet"

	if [ "${INSTALL_ERPNEXT:-yes}" = "yes" ]; then
		log_info "Installing ERPNext on site..."
		run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench --site '$SITE_NAME' install-app erpnext"
		log_success "ERPNext installed"
	else
		log_info "Skipping ERPNext installation"
	fi

	run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench --site '$SITE_NAME' enable-scheduler"
	run_as_frappe_user "$FRAPPE_USER" "cd '$BENCH_PATH' && bench --site '$SITE_NAME' set-maintenance-mode off"

	log_success "Development mode running on port $web_port"
}

create_dev_systemd_service() {
	log_info "Creating systemd service for development bench..."

	local service_name="bench-$BENCH_NAME"
	local service_file="/etc/systemd/system/${service_name}.service"

	sudo tee "$service_file" >/dev/null <<EOF
[Unit]
Description=Frappe Bench Development Server ($BENCH_NAME)
After=network.target mariadb.service redis-server.service

[Service]
Type=simple
User=$FRAPPE_USER
WorkingDirectory=$BENCH_PATH
ExecStart=/usr/local/bin/bench start
ExecStop=/bin/kill -TERM \$MAINPID
Restart=on-failure
RestartSec=10
StandardOutput=append:$BENCH_PATH/logs/bench.log
StandardError=append:$BENCH_PATH/logs/bench.log

[Install]
WantedBy=multi-user.target
EOF

	run_as_frappe_user "$FRAPPE_USER" "mkdir -p '$BENCH_PATH/logs'"
	log_success "Systemd service created: $service_name"
}
