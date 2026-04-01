#!/bin/bash
set -e

MOODLE_DB_NAME="moodle"
MOODLE_DB_USER="moodle"
MOODLE_DB_PASS="moodlepassword"

MYSQL_SOCK=/var/run/mysqld/mysqld.sock
MYSQL_ROOT="mysql -u root --password='' --socket=${MYSQL_SOCK}"

# ── MySQL directory & permission setup ────────────────────────────────────────
mkdir -p /var/run/mysqld /var/log/mysql
chown -R mysql:mysql /var/run/mysqld /var/log/mysql /var/lib/mysql
chmod 755 /var/run/mysqld

# ── First-run: initialise data directory ──────────────────────────────────────
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "==> Initialising MySQL data directory..."
    mysqld --initialize-insecure \
           --user=mysql \
           --datadir=/var/lib/mysql \
           --log-error=/var/log/mysql/error.log
    echo "==> MySQL data directory initialised."
fi

# ── Start MySQL normally ───────────────────────────────────────────────────────
echo "==> Starting MySQL..."
mysqld --user=mysql \
       --datadir=/var/lib/mysql \
       --socket=${MYSQL_SOCK} \
       --pid-file=/var/run/mysqld/mysqld.pid \
       --log-error=/var/log/mysql/error.log &

echo "==> Waiting for MySQL..."
for i in $(seq 1 30); do
    if mysqladmin ping --socket=${MYSQL_SOCK} --silent 2>/dev/null; then
        echo "==> MySQL is ready."
        chmod 755 /var/run/mysqld
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "==> MySQL failed to start. Error log:"
        cat /var/log/mysql/error.log
        exit 1
    fi
    sleep 2
done

# ── Create Moodle database and user (first run only) ──────────────────────────
if ! $MYSQL_ROOT -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA \
    WHERE SCHEMA_NAME='${MOODLE_DB_NAME}';" 2>/dev/null | grep -q "${MOODLE_DB_NAME}"; then

    echo "==> Creating Moodle database and user..."
    $MYSQL_ROOT <<EOF
CREATE DATABASE ${MOODLE_DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '${MOODLE_DB_USER}'@'localhost' IDENTIFIED BY '${MOODLE_DB_PASS}';
GRANT ALL PRIVILEGES ON ${MOODLE_DB_NAME}.* TO '${MOODLE_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    echo "==> Database and user created."
fi

# ── Moodle CLI install (first run only) ───────────────────────────────────────
if [ ! -f /var/www/html/moodle/config.php ]; then
    echo "==> Running Moodle CLI installer (this may take a few minutes)..."
    php /var/www/html/moodle/admin/cli/install.php \
        --wwwroot="http://localhost:8000" \
        --dataroot=/var/moodledata \
        --dbtype=mysqli \
        --dbhost=localhost \
        --dbsocket=${MYSQL_SOCK} \
        --dbname="${MOODLE_DB_NAME}" \
        --dbuser="${MOODLE_DB_USER}" \
        --dbpass="${MOODLE_DB_PASS}" \
        --fullname="WaterlooBae" \
        --shortname="WaterlooBae" \
        --adminuser=admin \
        --adminpass="Admin@1234" \
        --non-interactive \
        --agree-license

    chown www-data:www-data /var/www/html/moodle/config.php
    echo "==> Moodle installation complete."
else
    echo "==> Moodle already installed — skipping installer."
fi

# ── Start Moodle cron (runs every minute as www-data) ─────────────────────────
echo "==> Starting cron..."
echo "* * * * * www-data php /var/www/html/moodle/admin/cli/cron.php >> /var/log/moodle_cron.log 2>&1" \
    > /etc/cron.d/moodle
chmod 0644 /etc/cron.d/moodle
cron

# ── Start Apache in the foreground ────────────────────────────────────────────
echo "==> Starting Apache..."
exec apache2ctl -D FOREGROUND
