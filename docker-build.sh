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
	mkdir -p "$PGDATA"
	chown -R postgres "$PGDATA"
	chmod 700 "$PGDATA"

	mkdir -p /var/run/postgresql
	chown -R postgres /var/run/postgresql
	chmod 775 /var/run/postgresql

	# Create the transaction log directory before initdb is run (below) so the directory is owned by the correct user
	if [ "$POSTGRES_INITDB_WALDIR" ]; then
		mkdir -p "$POSTGRES_INITDB_WALDIR"
		chown -R postgres "$POSTGRES_INITDB_WALDIR"
		chmod 700 "$POSTGRES_INITDB_WALDIR"
	fi

	exec gosu postgres "$BASH_SOURCE"
fi

mkdir -p "$PGDATA"
chown -R "$(id -u)" "$PGDATA" 2>/dev/null || :
chmod 700 "$PGDATA" 2>/dev/null || :

# look specifically for PG_VERSION, as it is expected in the DB dir
if [ ! -s "$PGDATA/PG_VERSION" ]; then
	# "initdb" is particular about the current user existing in "/etc/passwd", so we use "nss_wrapper" to fake that if necessary
	# see https://github.com/docker-library/postgres/pull/253, https://github.com/docker-library/postgres/issues/359, https://cwrap.org/nss_wrapper.html
	if ! getent passwd "$(id -u)" &> /dev/null && [ -e /usr/lib/libnss_wrapper.so ]; then
		export LD_PRELOAD='/usr/lib/libnss_wrapper.so'
		export NSS_WRAPPER_PASSWD="$(mktemp)"
		export NSS_WRAPPER_GROUP="$(mktemp)"
		echo "postgres:x:$(id -u):$(id -g):PostgreSQL:$PGDATA:/bin/false" > "$NSS_WRAPPER_PASSWD"
		echo "postgres:x:$(id -g):" > "$NSS_WRAPPER_GROUP"
	fi

	if [ "$POSTGRES_INITDB_WALDIR" ]; then
		export POSTGRES_INITDB_ARGS="$POSTGRES_INITDB_ARGS --waldir $POSTGRES_INITDB_WALDIR"
	fi
	initdb --username="postgres"

	# unset/cleanup "nss_wrapper" bits
	if [ "${LD_PRELOAD:-}" = '/usr/lib/libnss_wrapper.so' ]; then
		rm -f "$NSS_WRAPPER_PASSWD" "$NSS_WRAPPER_GROUP"
		unset LD_PRELOAD NSS_WRAPPER_PASSWD NSS_WRAPPER_GROUP
	fi

	{
		echo
		echo "host all all all trust"
	} >> "$PGDATA/pg_hba.conf"

	# internal start of server in order to allow set-up using psql-client
	# does not listen on external TCP/IP and waits until start finishes
	PGUSER=postgres pg_ctl -D "$PGDATA" -o "-c listen_addresses=''" -w start

	psql=( psql -v ON_ERROR_STOP=1 --username "postgres" --no-password )

	echo "Create users: devuser devadmin"
	for USER in devuser devadmin; do
		"${psql[@]}" --set user="$USER" -f <(echo "CREATE USER :user WITH LOGIN;")
	done

	echo "Init database: devdb"
	"${psql[@]}" --dbname postgres --set db="devdb" <<-'EOSQL'
		CREATE DATABASE :"db" ;
	EOSQL

	echo "Grant admin privileges to: devadmin"
	"${psql[@]}" --set user="$USER" -f <(echo "ALTER DATABASE devdb OWNER TO devadmin;")

	echo "Apply init SQL"
	"${psql[@]}" --dbname "devdb" -f "/etc/docker-build.sql"

	PGUSER=postgres pg_ctl -D "$PGDATA" -m fast -w stop

	echo
	echo 'PostgreSQL init process complete; ready for start up.'
	echo
fi
