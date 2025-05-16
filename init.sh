#!/bin/bash

if [ -d "/home/frappe/frappe-bench/apps/frappe" ]; then
    echo "Bench already exists, skipping init"
    cd frappe-bench
    bench start
else
    echo "Creating new bench..."
fi

bench init --skip-redis-config-generation frappe-bench --version version-15

cd frappe-bench

# Set up the config file with proper Redis URLs
cat <<EOT > sites/common_site_config.json
{
 "background_workers": 1,
 "db_host": "mariadb",
 "file_watcher_port": 6787,
 "frappe_user": "frappe",
 "gunicorn_workers": 33,
 "live_reload": true,
 "rebase_on_pull": false,
 "redis_cache": "redis://redis:6379",
 "redis_queue": "redis://redis:6379",
 "redis_socketio": "redis://redis:6379",
 "restart_supervisor_on_update": false,
 "restart_systemd_on_update": false,
 "serve_default_site": true,
 "shallow_clone": true,
 "socketio_port": 9000,
 "use_redis_auth": false,
 "webserver_port": 8000
}
EOT

# Remove redis, watch from Procfile
sed -i '/redis/d' ./Procfile
sed -i '/watch/d' ./Procfile

bench get-app helpdesk --branch main

bench new-site localhost \
--force \
--mariadb-root-password 123 \
--admin-password admin \
--no-mariadb-socket

bench --site localhost install-app helpdesk
bench --site localhost set-config developer_mode 1
bench --site localhost set-config mute_emails 1
bench --site localhost set-config server_script_enabled 1
bench --site localhost clear-cache
bench use localhost

bench start
