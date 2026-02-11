#!/usr/bin/env bash
# Print installation completion summary

print_summary() {
	SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")

	echo ""
	echo "==========================================="
	echo "   INSTALLATION COMPLETE"
	echo "==========================================="
	echo ""
	echo "  Frappe     : $FRAPPE_VER"
	echo "  Python     : $PYTHON_BIN"
	echo "  Node.js    : $(node -v)"
	echo "  Bench      : $BENCH_PATH"
	echo "  Site       : $SITE_NAME"
	echo ""
	if [ -n "$DOMAIN" ]; then
		echo "  URL        : https://$DOMAIN"
	else
		echo "  URL        : http://$SERVER_IP:8000"
	fi
	echo ""
	echo "  Login:"
	echo "    Username : Administrator"
	echo "    Password : $ADMIN_PASS"
	echo ""
	echo "==========================================="
	echo ""
	echo "Commands:"
	echo "  cd $BENCH_PATH"
	echo "  bench start                    # Dev mode"
	echo "  bench restart                  # Production"
	echo "  sudo supervisorctl status      # Check services"
	echo ""
}
