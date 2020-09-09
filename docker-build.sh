#!/usr/bin/env bash

set -Eeo pipefail
# TODO swap to -Eeuo pipefail above (after handling all potentially-unset variables)

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

if [ "${1:0:1}" = '-' ]; then
	set -- postgres
fi

# allow the container to be started with `--user`
if [ "$(id -u)" = '0' ]; then
	echo "Started as user 'root'."
	mkdir -p /data /build/usr/share/postgresql.template
	chown -R postgres /data /build/usr/share/postgresql.template
	chmod 700 /data /build/usr/share/postgresql.template

	mkdir -p /run/postgresql /build/run/postgresql 
	chown -R postgres /run/postgresql /build/run/postgresql
	chmod 775 /run/postgresql /build/run/postgresql

	echo "Restarting as user 'postgres'..."
	exec su -c "$0" postgres -- "$@"
else
	echo "Started as user '$(id -u -n)'."
fi

mkdir -p /data
chown -R "$(id -u)" /data 2>/dev/null
chmod 700 /data 2>/dev/null

# look specifically for PG_VERSION, as it is expected in the DB dir
if [ ! -s "/data/PG_VERSION" ]; then

	echo "Initialize database backend directory"
	initdb -D /data --username="postgres"

	echo "Setup 'trust' for all hosts"
	{
		echo
		echo "host all all all trust"
	} >> "/data/pg_hba.conf"

	echo "Setup 'listen_addresses' to '0.0.0.0'"
	echo "listen_addresses = '0.0.0.0'" >> /data/postgresql.conf

	# internal start of server in order to allow set-up using psql-client
	# does not listen on external TCP/IP and waits until start finishes
	PGUSER=postgres pg_ctl -D /data -o "-c listen_addresses=''" -w start

	psql=( psql -v ON_ERROR_STOP=1 --username "postgres" --no-password )

	for USER in devuser devadmin; do
		echo "Create an user: ${USER}"
		"${psql[@]}" --set user="$USER" -f <(echo "CREATE USER :user WITH LOGIN;")
	done

	echo "Init database: devdb"
	"${psql[@]}" --dbname postgres --set db="devdb" <<-'EOSQL'
		CREATE DATABASE :"db" ;
	EOSQL

	echo "Grant admin privileges to: devadmin"
	"${psql[@]}" -f <(echo "ALTER DATABASE devdb OWNER TO devadmin;")

	echo "Apply init SQL"
	"${psql[@]}" --dbname "devdb" -f "/build-toolkit/docker-build.sql"

	PGUSER=postgres pg_ctl -D /data -m fast -w stop

	mv /data/* /build/usr/share/postgresql.template/

	echo
	echo 'PostgreSQL init process complete; ready for start up.'
	echo
fi
