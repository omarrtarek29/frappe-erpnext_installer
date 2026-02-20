#!/usr/bin/env bash
# Install bench CLI, initialize bench, get ERPNext, create site

install_bench_and_site() {
	log_info "Installing Frappe Bench..."

	sudo -u "$FRAPPE_USER" -H bash <<'BENCHINSTALL'
set -e
export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"
pipx ensurepath 2>/dev/null || true
if ! command -v bench &>/dev/null; then
    pipx install frappe-bench || pip3 install --user frappe-bench
fi
bench --version
BENCHINSTALL

	log_success "Bench installed"

	log_info "Initializing Bench..."

	sudo -u "$FRAPPE_USER" -H bash <<BENCHINIT
set -e
export PATH="/usr/local/bin:\$HOME/.local/bin:\$PATH"

cd "$FRAPPE_HOME"

if [ ! -d "$BENCH_PATH" ]; then
    bench init "$BENCH_PATH" \
        --python "$PYTHON_BIN" \
        --frappe-branch "$FRAPPE_BRANCH"
else
    echo "Bench already exists"
fi

cd "$BENCH_PATH"

if [ ! -d "apps/erpnext" ]; then
    bench get-app erpnext --branch "$FRAPPE_BRANCH"
fi

if [ "$FRAPPE_VER" = "15" ]; then
    ./env/bin/pip install --upgrade pip
    ./env/bin/pip install "setuptools>=58,<75"
fi

if [ ! -d "sites/$SITE_NAME" ]; then
    if [ -n "$MYSQL_ROOT_PASS" ]; then
        bench new-site "$SITE_NAME" \
            --admin-password "$ADMIN_PASS" \
            --mariadb-root-password "$MYSQL_ROOT_PASS"
    else
        bench new-site "$SITE_NAME" \
            --admin-password "$ADMIN_PASS"
    fi
fi

bench use "$SITE_NAME"
BENCHINIT

	log_success "Bench initialized"
}
