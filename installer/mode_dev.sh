#!/usr/bin/env bash
# Development: start bench, wait for Redis, optionally install ERPNext on site

setup_dev_mode() {
	log_info "Starting development mode..."

	sudo -u "$FRAPPE_USER" -H bash <<DEVMODE
set -e
export PATH="/usr/local/bin:\$HOME/.local/bin:\$PATH"

cd "$BENCH_PATH"

nohup bench start > bench.log 2>&1 &
BENCH_PID=\$!
echo "Bench started with PID: \$BENCH_PID"

sleep 10

for i in {1..30}; do
    if redis-cli -p 11001 ping &>/dev/null; then
        echo "Redis Queue is ready"
        break
    fi
    echo "Waiting for Redis Queue... (\$i/30)"
    sleep 2
done

if [ "${INSTALL_ERPNEXT:-yes}" = "yes" ]; then
    echo "Installing ERPNext on site..."
    bench --site "$SITE_NAME" install-app erpnext
    bench --site "$SITE_NAME" enable-scheduler
    bench --site "$SITE_NAME" set-maintenance-mode off
    echo "ERPNext installation complete"
else
    echo "Skipping ERPNext installation (user chose not to install)."
fi
DEVMODE

	log_success "Development mode running"
}
