#!/bin/bash

set -e
trap '[ $? -eq 0 ] && exit 0 || echo "sdms failed with exit status $?"' EXIT

# Help function
sdms_help() {
    echo "sdms"
    echo "Usage: sdms --deploy email hostname"
    echo "       sdms --new domain"
    echo "       sdms --ssl domain"
    echo "       sdms --delete domain"
    echo "       sdms --backup"
}

# Get PHP version function
sdms_php() {
    # Get latest PHP folder
    if [ -d "/etc/php" ]; then
        sdms_php="$(ls /etc/php | sort -nr | head -n1)"
    fi

    # Check php.ini files exist
    if [ ! -f "/etc/php/$sdms_php/fpm/php.ini" ] || [ ! -f "/etc/php/$sdms_php/cli/php.ini" ]; then
        echo "sdms could not find php" >&2
        exit 1
    fi
}

# Password generation function
sdms_pass() {
    sdms_length=$1
    if [ -z "$sdms_length" ]; then
        sdms_length=16
    fi

    tr -dc 'a-zA-Z0-9-_!@#$%^&*\()_+{}|:<>?=' < /dev/urandom | head -c "${sdms_length}" | xargs
}

# Deploy function
sdms_deploy() {
    sdms_email="$1"
    sdms_hostname="$2"

    # Update and install packages
    DEBIAN_FRONTEND=noninteractive apt-get -qy update
    DEBIAN_FRONTEND=noninteractive apt-get -qy dist-upgrade
    DEBIAN_FRONTEND=noninteractive apt-get -qy install ca-certificates certbot composer curl git libnginx-mod-http-headers-more-filter libnginx-mod-http-uploadprogress mariadb-client mariadb-server nftables nginx php-cli php-curl php-fpm php-gd php-json php-mbstring php-mysql php-xml php-zip unattended-upgrades unzip wget zip

    # Set hostname
    hostnamectl set-hostname "$sdms_hostname"

    # Set timezone to UTC
    timedatectl set-timezone UTC

    # Enable unattended upgrades
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -plow unattended-upgrades

    # Configure git
    git config --global pull.rebase false

    # Configure nftables
    {
        echo '#!/usr/sbin/nft -f'
        echo 'flush ruleset'
        echo ''
        echo 'table inet filter {'
        echo '\tchain input {'
        echo '\t\ttype filter hook input priority 0;'
        echo ''
        echo '\t\t# Accept any localhost traffic'
        echo '\t\tiif lo accept'
        echo ''
        echo '\t\t# Accept traffic originated from us'
        echo '\t\tct state established,related accept'
        echo ''
        echo '\t\t# Accept SSH and web server traffic'
        echo '\t\ttcp dport { 22, 80, 443 } ct state new accept'
        echo ''
        echo '\t\t# Accept ICMP traffic'
        echo '\t\tip protocol icmp accept'
        echo '\t\tip6 nexthdr icmpv6 accept'
        echo ''
        echo '\t\t# Count and drop any other traffic'
        echo '\t\tcounter drop'
        echo '\t}'
        echo '}'
    } > /etc/nftables.conf
    nft -f /etc/nftables.conf
    systemctl enable nftables.service

    # Secure MariaDB server
    mariadb -e "DELETE FROM mysql.user WHERE User='';"
    mariadb -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
    mariadb -e "DROP DATABASE IF EXISTS test;"
    mariadb -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
    mariadb -e "FLUSH PRIVILEGES;"

    # Generate Diffie–Hellman parameters
    touch /etc/nginx/dhparams.pem
    chmod o-r,o-w /etc/nginx/dhparams.pem
    openssl dhparam -out /etc/nginx/dhparams.pem 2048

    # Configure NGINX
    if [ -f /etc/nginx/nginx.conf ]; then
        # Hide NGINX version
        sed -i -e 's/# server_tokens off;/server_tokens off;\n\tmore_clear_headers Server;/g' /etc/nginx/nginx.conf

        # Enable gzip
        sed -i -e 's/# gzip on;/gzip on;/g' /etc/nginx/nginx.conf

        # Disable gzip for IE6
        sed -i -e 's/# gzip_disable "msie6";/gzip_disable "msie6";/g' /etc/nginx/nginx.conf

        # Enable gzip for proxies
        sed -i -e 's/# gzip_proxied any;/gzip_proxied any;/g' /etc/nginx/nginx.conf

        # Enable gzip vary
        sed -i -e 's/# gzip_vary on;/gzip_vary on;/g' /etc/nginx/nginx.conf

        # Increase gzip level
        sed -i -e 's/# gzip_comp_level/gzip_comp_level/g' /etc/nginx/nginx.conf

        # Set minimum gzip length
        sed -i -e 's/# gzip_types/gzip_min_length 256;\n\t# gzip_types/g' /etc/nginx/nginx.conf

        # Enable gzip for all applicable files
        sed -i -e 's/# gzip_types/gzip_types application\/vnd.ms-fontobject application\/x-font-ttf font\/opentype image\/svg+xml image\/x-icon;\n\t# gzip_types/g' /etc/nginx/nginx.conf

        # Set client header timeout
        sed -i -e 's/# client_header_timeout/client_header_timeout/g' /etc/nginx/nginx.conf

        # Set client body timeout
        sed -i -e 's/# client_body_timeout/client_body_timeout/g' /etc/nginx/nginx.conf

        # Set send timeout
        sed -i -e 's/# send_timeout/send_timeout/g' /etc/nginx/nginx.conf

        # Increase buffers
        sed -i -e 's/# tcp_nopush/tcp_nopush/g' /etc/nginx/nginx.conf
        sed -i -e 's/# tcp_nodelay/tcp_nodelay/g' /etc/nginx/nginx.conf
        sed -i -e 's/# keepalive_timeout/keepalive_timeout/g' /etc/nginx/nginx.conf
        sed -i -e 's/# keepalive_requests/keepalive_requests/g' /etc/nginx/nginx.conf
        sed -i -e 's/# reset_timedout_connection/reset_timedout_connection/g' /etc/nginx/nginx.conf
        sed -i -e 's/# server_names_hash_bucket/server_names_hash_bucket/g' /etc/nginx/nginx.conf

        # Disable HTTP/2
        sed -i -e 's/listen 443 ssl http2;/listen 443 ssl;/g' /etc/nginx/nginx.conf
    fi

    # Configure PHP
    if [ -f "/etc/php/$sdms_php/fpm/php.ini" ]; then
        # Enable output_buffering
        sed -i -e 's/output_buffering = .*/output_buffering = 4096/g' "/etc/php/$sdms_php/fpm/php.ini"

        # Enable zlib.output_compression
        sed -i -e 's/;zlib.output_compression = .*/zlib.output_compression = On/g' "/etc/php/$sdms_php/fpm/php.ini"

        # Increase memory_limit
        sed -i -e 's/memory_limit = .*/memory_limit = 256M/g' "/etc/php/$sdms_php/fpm/php.ini"

        # Enable upload_max_filesize
        sed -i -e 's/upload_max_filesize = .*/upload_max_filesize = 64M/g' "/etc/php/$sdms_php/fpm/php.ini"

        # Enable post_max_size
        sed -i -e 's/post_max_size = .*/post_max_size = 64M/g' "/etc/php/$sdms_php/fpm/php.ini"

        # Enable max_execution_time
        sed -i -e 's/max_execution_time = .*/max_execution_time = 300/g' "/etc/php/$sdms_php/fpm/php.ini"

        # Enable max_input_time
        sed -i -e 's/max_input_time = .*/max_input_time = 300/g' "/etc/php/$sdms_php/fpm/php.ini"

        # Enable opcache
        sed -i -e 's/;opcache.enable=1/opcache.enable=1/g' "/etc/php/$sdms_php/fpm/php.ini"

        # Enable opcache.interned_strings_buffer
        sed -i -e 's/;opcache.interned_strings_buffer=8/opcache.interned_strings_buffer=8/g' "/etc/php/$sdms_php/fpm/php.ini"

        # Enable opcache.max_accelerated_files
        sed -i -e 's/;opcache.max_accelerated_files=10000/opcache.max_accelerated_files=10000/g' "/etc/php/$sdms_php/fpm/php.ini"

        # Enable opcache.memory_consumption
        sed -i -e 's/;opcache.memory_consumption=128/opcache.memory_consumption=128/g' "/etc/php/$sdms_php/fpm/php.ini"

        # Enable opcache.save_comments
        sed -i -e 's/;opcache.save_comments=1/opcache.save_comments=1/g' "/etc/php/$sdms_php/fpm/php.ini"

        # Enable opcache.revalidate_freq
        sed -i -e 's/;opcache.revalidate_freq=2/opcache.revalidate_freq=2/g' "/etc/php/$sdms_php/fpm/php.ini"
    fi

    # Enable and start PHP-FPM
    systemctl enable php$sdms_php-fpm
    systemctl start php$sdms_php-fpm

    # Configure fail2ban
    touch /etc/fail2ban/jail.local
    echo "[sshd]" >> /etc/fail2ban/jail.local
    echo "enabled = true" >> /etc/fail2ban/jail.local
    echo "port = ssh" >> /etc/fail2ban/jail.local
    echo "filter = sshd" >> /etc/fail2ban/jail.local
    echo "logpath = /var/log/auth.log" >> /etc/fail2ban/jail.local
    echo "maxretry = 3" >> /etc/fail2ban/jail.local
    systemctl enable fail2ban
    systemctl start fail2ban

    # Configure logrotate
    {
        echo "/var/log/*.log {"
        echo "    daily"
        echo "    missingok"
        echo "    rotate 7"
        echo "    compress"
        echo "    delaycompress"
        echo "    notifempty"
        echo "    create 0640 root adm"
        echo "    sharedscripts"
        echo "    postrotate"
        echo "        invoke-rc.d rsyslog rotate > /dev/null"
        echo "    endscript"
        echo "}"
    } > /etc/logrotate.d/sdms

    # Set unattended-upgrades
    {
        echo 'Unattended-Upgrade::Allowed-Origins {'
        echo '        "${distro_id}:${distro_codename}-security";'
        echo '};'
        echo 'Unattended-Upgrade::Package-Blacklist {'
        echo '};'
        echo 'Unattended-Upgrade::DevRelease "false";'
        echo 'Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";'
        echo 'Unattended-Upgrade::Automatic-Reboot "false";'
    } > /etc/apt/apt.conf.d/50unattended-upgrades

    # Update unattended-upgrades
    unattended-upgrade

    # Generate random MySQL root password
    sdms_mysql_pass=$(sdms_pass)

    # Configure MySQL
    mariadb -e "UPDATE mysql.user SET Password = PASSWORD('$sdms_mysql_pass') WHERE User = 'root';"
    mariadb -e "FLUSH PRIVILEGES;"

    # Save MySQL root password
    echo "MySQL root password: $sdms_mysql_pass" > /root/mysql_root_password.txt

    # Deploy complete
    echo "sdms has successfully deployed."
    echo "MySQL root password has been saved to /root/mysql_root_password.txt."
}

# New domain function
sdms_new() {
    sdms_domain="$1"

    # Create NGINX server block
    {
        echo "server {"
        echo "    listen 80;"
        echo "    server_name $sdms_domain;"
        echo "    root /var/www/$sdms_domain;"
        echo ""
        echo "    index index.php;"
        echo ""
        echo "    location / {"
        echo "        try_files \$uri \$uri/ /index.php?\$args;"
        echo "    }"
        echo ""
        echo "    location ~ \.php\$ {"
        echo "        include fastcgi_params;"
        echo "        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;"
        echo "        fastcgi_pass unix:/var/run/php/php$sdms_php-fpm.sock;"
        echo "        fastcgi_index index.php;"
        echo "    }"
        echo "}"
    } > /etc/nginx/sites-available/$sdms_domain.conf
    ln -s /etc/nginx/sites-available/$sdms_domain.conf /etc/nginx/sites-enabled/$sdms_domain.conf

    # Restart NGINX
    systemctl restart nginx

    # Create web directory
    mkdir -p /var/www/$sdms_domain

    # Create index.php
    echo "<?php phpinfo(); ?>" > /var/www/$sdms_domain/index.php

    # Set permissions
    chown -R www-data:www-data /var/www/$sdms_domain
    chmod -R 755 /var/www/$sdms_domain

    # New domain complete
    echo "New domain $sdms_domain has been created."
}

# SSL function
sdms_ssl() {
    sdms_domain="$1"

    # Request SSL certificate
    certbot --nginx -d $sdms_domain

    # SSL complete
    echo "SSL certificate has been configured for $sdms_domain."
}

# Delete domain function
sdms_delete() {
    sdms_domain="$1"

    # Delete NGINX server block
    rm /etc/nginx/sites-available/$sdms_domain.conf
    rm /etc/nginx/sites-enabled/$sdms_domain.conf

    # Delete web directory
    rm -rf /var/www/$sdms_domain

    # Restart NGINX
    systemctl restart nginx

    # Delete domain complete
    echo "Domain $sdms_domain has been deleted."
}

# Backup function
sdms_backup() {
    # Backup databases
    mysqldump --all-databases > /root/databases.sql

    # Backup NGINX server blocks
    tar -czvf /root/nginx_conf.tar.gz /etc/nginx/sites-available/ /etc/nginx/sites-enabled/

    # Backup complete
    echo "Backup has been completed."
}

# Main function
main() {
    if [ "$#" -lt 1 ]; then
        sdms_help
        exit 1
    fi

    case "$1" in
        --deploy)
            if [ "$#" -ne 3 ]; then
                sdms_help
                exit 1
            fi
            sdms_php
            sdms_deploy "$2" "$3"
            ;;
        --new)
            if [ "$#" -ne 2 ]; then
                sdms_help
                exit 1
            fi
            sdms_new "$2"
            ;;
        --ssl)
            if [ "$#" -ne 2 ]; then
                sdms_help
                exit 1
            fi
            sdms_ssl "$2"
            ;;
        --delete)
            if [ "$#" -ne 2 ]; then
                sdms_help
                exit 1
            fi
            sdms_delete "$2"
            ;;
        --backup)
            sdms_backup
            ;;
        *)
            sdms_help
            exit 1
            ;;
    esac
}

# Run main function with provided arguments
main "$@"
