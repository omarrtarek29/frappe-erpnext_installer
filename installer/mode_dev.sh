#!/usr/bin/env bash

setup_dev_mode() {
	log_info "Setting up development mode..."

	stop_supervisor_bench "$BENCH_NAME"
	disable_dev_systemd_service
	stop_bench_processes "$BENCH_PATH" "$FRAPPE_USER"
	free_bench_ports "$BENCH_PATH"
	configure_bench_redis
	prepare_bench_logs

	local web_port
	web_port=$(get_webserver_port "$BENCH_PATH")

	export DEV_WEB_PORT="$web_port"

	log_success "Development bench ready"
	echo ""
	echo "  Next step — start the dev server:"
	echo ""
	echo "    cd ~/$BENCH_NAME"
	echo "    bench serve --port $web_port"
	echo ""
	echo "  Then open: http://$(hostname -I 2>/dev/null | awk '{print $1}'):$web_port"
}
