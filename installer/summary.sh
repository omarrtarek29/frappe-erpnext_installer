#!/usr/bin/env bash

print_summary() {
	SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
	local bench_name
	bench_name=$(basename "$BENCH_PATH")

	echo ""
	echo "==========================================="
	echo "   INSTALLATION COMPLETE"
	echo "==========================================="
	echo ""
	echo "  Frappe     : $FRAPPE_VER ($FRAPPE_BRANCH)"
	echo "  Python     : ${PYTHON_BIN:-python3}"
	echo "  Node.js    : $(node -v 2>/dev/null || echo 'N/A')"
	echo "  Bench      : $BENCH_PATH"
	echo "  Bench bin  : /usr/local/bin/bench (global)"
	echo "  Site       : $SITE_NAME"
	echo ""
	if [ -n "$DOMAIN" ]; then
		echo "  Mode       : Production"
		echo "  URL        : https://$DOMAIN"
	else
		local web_port
		web_port="${DEV_WEB_PORT:-$(get_webserver_port "$BENCH_PATH")}"
		echo "  Mode       : Development"
		echo "  URL        : http://$SERVER_IP:$web_port (after starting bench serve)"
	fi
	echo ""
	echo "  Login:"
	echo "    Username : Administrator"
	echo "    Password : (as configured)"
	echo ""
	echo "==========================================="
	echo ""
	if [ -n "$DOMAIN" ]; then
		echo "Production Commands:"
		echo "  sudo supervisorctl status           # Check all services"
		echo "  sudo supervisorctl restart all      # Restart services"
		echo "  bench --site $SITE_NAME migrate     # Run migrations"
		echo "  bench --site $SITE_NAME backup      # Create backup"
		echo ""
		echo "Service Management:"
		echo "  sudo systemctl status nginx"
		echo "  sudo systemctl status supervisor"
	else
		local web_port
		web_port="${DEV_WEB_PORT:-$(get_webserver_port "$BENCH_PATH")}"
		echo "Common Commands:"
		echo "  bench --site $SITE_NAME console       # Python console"
		echo "  bench --site $SITE_NAME mariadb       # Database shell"
		echo "  bench get-app <app-name>              # Install app"
		echo ""
		echo "==========================================="
		echo ""
		echo "  Next step — start the dev server:"
		echo ""
		echo "    cd ~/$bench_name"
		echo "    bench serve --port $web_port"
		echo ""
		echo "  Then open: http://$SERVER_IP:$web_port"
		echo ""
	fi

	if [ -n "$DOMAIN" ]; then
		echo "Common Commands:"
		echo "  cd $BENCH_PATH"
		echo "  bench --site $SITE_NAME console       # Python console"
		echo "  bench --site $SITE_NAME mariadb       # Database shell"
		echo "  bench get-app <app-name>              # Install app"
		echo ""
	fi
}
