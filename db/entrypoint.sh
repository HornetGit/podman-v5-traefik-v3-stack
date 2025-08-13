#!/bin/sh

# note: $PGDATA defined by postgres as env

mkdir -p /run/postgresql
chown postgres:postgres /run/postgresql

# Change default socket path (optional)
sed -i "s|#unix_socket_directories =.*|unix_socket_directories = '/tmp'|" "$PGDATA/postgresql.conf"

# Harden pg_hba.conf (optional)
sed -i "s|host all all.*trust|host all all 0.0.0.0/0 md5|" "$PGDATA/pg_hba.conf"

# Start default entrypoint (and thus, postgres: no need to daemonize the container)
exec docker-entrypoint.sh postgres