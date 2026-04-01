# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-container Docker setup that runs **Moodle 5.1** (branch `MOODLE_501_STABLE`) with **MySQL 8.4** and **PHP 8.5** on **Ubuntu 26.04 (Resolute)**, served by Apache on port 8000.

Everything — Apache, PHP, and MySQL — runs inside one container (`moodle_app`). There is no separate database container.

## Key commands

```bash
# First build and start
docker compose up --build

# Start after initial build
docker compose up

# Wipe all data and start clean (required when changing MySQL version or fixing broken state)
docker compose down -v
docker compose up --build

# Rebuild image only (no volume wipe)
docker compose up --build

# View live logs
docker logs -f moodle_app

# View only meaningful log lines (filters deprecation noise)
docker logs -f moodle_app 2>&1 | grep -E "(Success|failed|Starting Apache|installation complete|ERROR|==>)"

# Open a shell inside the running container
docker exec -it moodle_app bash

# Check MySQL is alive
docker exec moodle_app mysqladmin ping --socket=/var/run/mysqld/mysqld.sock --silent

# Connect to MySQL as root
docker exec -it moodle_app mysql -u root --password='' --socket=/var/run/mysqld/mysqld.sock

# Connect to MySQL as moodle user
docker exec -it moodle_app mysql -u moodle -pmoodlepassword --socket=/var/run/mysqld/mysqld.sock moodle

# Run Moodle CLI tools
docker exec moodle_app php /var/www/html/moodle/admin/cli/<script>.php
```

## Site access

- **URL:** `http://localhost:8000`
- **Admin login:** `admin` / `Admin@1234`

## Architecture

### Container startup sequence (`entrypoint.sh`)

The entrypoint runs every time the container starts and is idempotent:

1. Creates `/var/run/mysqld` with `chmod 755` — critical so `www-data` (Apache) can reach the socket
2. Initialises MySQL data directory with `--initialize-insecure` (root gets empty password) — **only on first run** (guarded by `[ ! -d /var/lib/mysql/mysql ]`)
3. Starts `mysqld` as background process using the socket at `/var/run/mysqld/mysqld.sock`
4. Creates the `moodle` database and user — **only on first run** (guarded by schema existence check)
5. Runs the Moodle CLI installer — **only on first run** (guarded by `[ ! -f config.php ]`)
6. Starts Apache in the foreground (`exec apache2ctl -D FOREGROUND`)

### Volumes

| Volume | Mount point | Purpose |
|---|---|---|
| `mysql_data` | `/var/lib/mysql` | MySQL data directory |
| `moodle_html` | `/var/www/html/moodle` | Moodle source + `config.php` |
| `moodle_data` | `/var/moodledata` | Moodle user files, cache, sessions |

### MySQL socket vs TCP

All MySQL connections (root setup, Moodle installer, and Moodle runtime) use the Unix socket at `/var/run/mysqld/mysqld.sock`, not TCP. This is set in `config.php` under `dboptions['dbsocket']`. The `/var/run/mysqld/` directory must be `755` (not `700`) so `www-data` can reach the socket — this is set in `entrypoint.sh`.

### PHP configuration

PHP 8.5 comes from Ubuntu 26.04's default repos (no PPA needed). The ini settings for both the Apache module (`/etc/php/8.5/apache2/php.ini`) and CLI (`/etc/php/8.5/cli/php.ini`) are tuned in the Dockerfile — both must be set because the Moodle CLI installer uses CLI PHP.

### Known deprecation warnings

Moodle 5.1 produces PHP 8.5 deprecation warnings (`E_STRICT`, `xml_parser_free`, backtick operator, etc.) during installation and runtime. These are Moodle compatibility issues with PHP 8.5 and do not affect functionality.

## When things go wrong

**"Database connection failed" on the web UI** — Check that `/var/run/mysqld/` is `chmod 755`. If it was created as `700` (MySQL default), `www-data` cannot access the socket.

**"Access denied for user root"** — The `mysql_data` volume has stale data. Run `docker compose down -v` then rebuild.

**MySQL fails to start** — Check the error log: `docker exec moodle_app cat /var/log/mysql/error.log`

**Moodle installer skipped but config.php is missing/corrupt** — The `moodle_html` volume has partial state. Run `docker compose down -v` then rebuild.
