[![Docker Build Status](https://img.shields.io/docker/build/zxteamorg/devel.postgres-10?label=Build%20Status)](https://hub.docker.com/r/zxteamorg/devel.postgres-10/builds)
[![Docker Image Size (latest by date)](https://img.shields.io/docker/image-size/zxteamorg/devel.postgres-10?label=Image%20Size)](https://hub.docker.com/r/zxteamorg/devel.postgres-10/tags)
[![Docker Pulls](https://img.shields.io/docker/pulls/zxteamorg/devel.postgres-10?label=Pulls)](https://hub.docker.com/r/zxteamorg/devel.postgres-10)
[![Docker Image Version (latest by date)](https://img.shields.io/docker/v/zxteamorg/devel.postgres-10?sort=semver&label=Version)](https://hub.docker.com/r/zxteamorg/devel.postgres-10/tags)
[![Docker Image Info](https://images.microbadger.com/badges/image/zxteamorg/devel.postgres-10.svg)](https://hub.docker.com/r/zxteamorg/devel.postgres-10/dockerfile)

# Postgres
[PostgreSQL](https://www.postgresql.org/) is a powerful, open source object-relational database system with over 30 years of active development that has earned it a strong reputation for reliability, feature robustness, and performance

# Image reason
For development and testing purposes we need pre-setup Postgres server to automate development and auto-testing actvity. The container has pre-defined empty database (with flag table to ensure non-production case) and two users.

# Inside
* PostgreSQL 10.14 Server
* Database `devdb`
* Flag table `devdb.publc.devflag`
* User `postgres` - superuser
* User `devadmin` - owner of the database `devdb`
* User `devuser` - regular user

# Launch
1. Start development server
	```bash
	docker run --interactive --tty --rm --publish 5432:5432 zxteamorg/devel.postgres-10
	```
1. Use connection strings (no password):
	* `postgres://postgres@127.0.0.1:5432/postgres` - to login as superuser
	* `postgres://devadmin@127.0.0.1:5432/devdb` - to login as `devdb` owner
	* `postgres://devuser@127.0.0.1:5432/devdb` - to login as regular user
