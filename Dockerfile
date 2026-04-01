FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

# Ubuntu 26.04 (Resolute) ships both PHP 8.5 and MySQL 8.4 natively.
# No external PPAs or repos needed.

# Prevent apt from trying to start services during install (container-safe)
RUN echo '#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d

# ── Install all packages ───────────────────────────────────────────────────────
# Ubuntu 26.04 (Resolute) ships MySQL 8.4 by default — no external repo needed.
RUN apt-get update && apt-get install -y \
    # Web server
    apache2 \
    # PHP 8.5 + Apache module
    php8.5 \
    libapache2-mod-php8.5 \
    php8.5-cli \
    # PHP extensions required by Moodle
    php8.5-mysql \
    php8.5-xml \
    php8.5-curl \
    php8.5-zip \
    php8.5-gd \
    php8.5-mbstring \
    php8.5-intl \
    php8.5-soap \
    # MySQL 8.4 (Ubuntu 26.04 default)
    mysql-server \
    # Utilities
    git \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# ── PHP tuning (both Apache and CLI, so installer + runtime both pass) ─────────
RUN for INI in /etc/php/8.5/apache2/php.ini /etc/php/8.5/cli/php.ini; do \
        echo "max_input_vars = 5000"        >> $INI; \
        echo "upload_max_filesize = 64M"    >> $INI; \
        echo "post_max_size = 64M"          >> $INI; \
        echo "memory_limit = 256M"          >> $INI; \
    done

# ── Clone Moodle 5.1 ───────────────────────────────────────────────────────────
RUN git clone --depth=1 --branch MOODLE_501_STABLE \
    https://github.com/moodle/moodle.git /var/www/html/moodle

# ── Moodle data directory (must be outside web root) ──────────────────────────
RUN mkdir -p /var/moodledata \
    && chown -R www-data:www-data /var/moodledata \
    && chmod 770 /var/moodledata

# ── Web root permissions ───────────────────────────────────────────────────────
RUN chown -R www-data:www-data /var/www/html/moodle

# ── Apache configuration ───────────────────────────────────────────────────────
RUN a2enmod rewrite

COPY moodle.conf /etc/apache2/sites-available/moodle.conf
RUN a2ensite moodle.conf \
    && a2dissite 000-default.conf

# ── Entrypoint ────────────────────────────────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
