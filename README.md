# SDMS
A simple LEMP (Linux, NGINX, MariaDB, PHP) server deployment and management script supporting Debian 9 and later. It is tested as working on Debian 9 (Stretch), 10 (Buster), 11 (Bullseye) and 12 (Bookworm). Intended for virtual hosting environments, this script enables the automated creation and removal of domains in the LEMP stack.

By default there are no deb repository or compilation requirements, solely using packages provided and maintained by Debian for ease of upgrade and security. Some associated scripts are provided (generally for edge cases or newer software versions).

When upgrading from one Debian release to the next, the script remains compatible and the server should continue running smoothly subject to you manually moving PHP pool config files to the new location (for example for Debian 11 to 12, PHP pools need moving from `/etc/php/7.4/pool.d/` to `/etc/php/8.2/pool.d/`).

SDMS is made available under the MIT licence.

## Features

* Server hardening along with secure configuration
  * nftables firewall
  * Unattended upgrades
  * Diffie-Hellman parameters generation
  * Banner removal
* NGINX and PHP-FPM virtual host management
  * Add domain
  * Remove domain
  * Let's Encrypt SSL
* Backup of databases, SSL certificates, website files and configuration files

## Usage
### Deploy server
```sh
$ ./sdms.sh --deploy email hostname
```
The `--deploy` option is intended to be run on a fresh installation, installing required packages and performing initial setup.

The email is used for the Let's Encrypt account. The hostname should be a fully qualified domain name.

### New domain
```sh
$ ./sdms.sh --new domain
```
The `--new` option creates a full LEMP virtual host for the given domain, which includes a web directory in `/srv/www`, a database, and a PHP-FPM pool.

### Generate SSL
```sh
$ ./sdms.sh --ssl domain
```
The `--ssl` option uses Let's Encrypt to generate a SSL certificate for the given domain and produces a relevant NGINX configuration file. Please note this overwrites the current configuration file for the domain.

### Delete domain
```sh
$ ./sdms.sh --delete domain
```
The `--delete` option simply deletes the given domain, including it's web directory, database, relevant configuration files, and SSL certificates.

### Backup

```sh
$ ./sdms.sh --backup
```
The `--backup` option performs a dump of all databases, and a backup of all SSL certificates, website files and configuration files.
