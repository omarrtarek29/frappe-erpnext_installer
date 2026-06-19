#!/usr/bin/env bash

install_bench_and_site() {
	install_bench_globally

	log_info "Initializing Bench..."

	local site_flags=""
	if [ "${FORCE_SITE:-no}" = "yes" ]; then
		site_flags="--force"
	fi

	local admin_pass_escaped
	admin_pass_escaped=$(printf '%s' "$ADMIN_PASS" | sed 's/[&/\]/\\&/g')
	local mysql_pass_escaped=""
	if [ -n "${MYSQL_ROOT_PASS:-}" ]; then
		mysql_pass_escaped=$(printf '%s' "$MYSQL_ROOT_PASS" | sed 's/[&/\]/\\&/g')
	fi

	sudo -u "$FRAPPE_USER" -H bash -c "
set -e
export PATH=\"/usr/local/bin:/usr/bin:/bin\"
export ADMIN_PASS='$admin_pass_escaped'
export MYSQL_ROOT_PASS='$mysql_pass_escaped'

cd \"$FRAPPE_HOME\"

if [ ! -d \"$BENCH_PATH\" ]; then
    bench init \"$BENCH_PATH\" --python \"$PYTHON_BIN\" --frappe-branch \"$FRAPPE_BRANCH\"
else
    echo 'Bench already exists at $BENCH_PATH'
fi

cd \"$BENCH_PATH\"

if [ ! -d \"apps/erpnext\" ]; then
    bench get-app erpnext --branch \"$FRAPPE_BRANCH\"
else
    echo 'ERPNext app already present'
fi

if [ \"$FRAPPE_VER\" = \"15\" ]; then
    ./env/bin/pip install --upgrade pip
    ./env/bin/pip install 'setuptools>=58,<75'
fi

if [ ! -d \"sites/$SITE_NAME\" ] || [ \"${FORCE_SITE:-no}\" = \"yes\" ]; then
    if [ -n \"\$MYSQL_ROOT_PASS\" ]; then
        bench new-site \"$SITE_NAME\" $site_flags --admin-password \"\$ADMIN_PASS\" --mariadb-root-password \"\$MYSQL_ROOT_PASS\"
    else
        bench new-site \"$SITE_NAME\" $site_flags --admin-password \"\$ADMIN_PASS\"
    fi
fi

bench use \"$SITE_NAME\"
"

	log_success "Bench initialized with site $SITE_NAME"
}
