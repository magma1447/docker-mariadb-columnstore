# MariaDB ColumnStore Docker

A single-node MariaDB ColumnStore image, built from the official [MariaDB Docker image](https://hub.docker.com/_/mariadb) and the ColumnStore storage engine plugin, built from MariaDB's source with fixes (see [Patches](#patches)).

The [official MariaDB ColumnStore images](https://hub.docker.com/r/mariadb/columnstore) have not been updated since 2023 (23.02.x). ColumnStore itself has moved on and is now shipped as a plugin package for the regular MariaDB server, so this image adds it to the regular server image instead.

## What This Provides

- **MariaDB 13.0.2** from the official `mariadb:13.0.2` image.
- **ColumnStore 25.10.7**, the version MariaDB 13.0.2 ships, built from source with the fixes in `patches/` (see [Patches](#patches)).
- **Single node**, without CMAPI (ColumnStore's cluster management API), which is not in MariaDB's community repository.
- **The official image's entrypoint**, so its `MARIADB_*` environment variables and `/docker-entrypoint-initdb.d/` work as usual.
- **ColumnStore's logs in `docker logs`.**

## Tags

- `latest` - Built from `Dockerfile` on the `main` branch.
- `ack-overflow` - Built from the `fix/ack-overflow` branch, with ColumnStore patched.

## Patches

On the `fix/ack-overflow` branch, the image doesn't install MariaDB's `mariadb-plugin-columnstore` package. A build stage builds MariaDB's packages from the source tag of the base image's release, the way MariaDB builds its own (`debian/autobake-deb.sh`), with the patches in `patches/` applied to ColumnStore. The final image installs the ColumnStore package from that build.

- `ack-overflow.patch` - The query engine hangs in an endless loop, logging `DEC::nextPMToACK(): Couldn't find a PM to ACK! 0  max: 65536` without end, when it acknowledges a batch of exactly 65536 messages: the count travels in a 16-bit field and becomes 0. The patch acknowledges at most 65535 messages at a time, and logs `DEC::sendAcks(): splitting ...` when it splits a batch. Upstream's fix for this (MCOL-5602) was reverted in 2024 and not redone.

The build takes a while and needs a few tens of GB for Docker's build cache:

```bash
docker build -t ghcr.io/magma1447/docker-mariadb-columnstore:ack-overflow .
```

## Quick Start

```bash
git clone https://github.com/magma1447/docker-mariadb-columnstore.git
cd docker-mariadb-columnstore

# The first start initializes the server and ColumnStore's system catalog.
docker compose up -d
docker compose logs -f

# Connect to MariaDB. Default password: C0lumnStore!
docker compose exec mcs mariadb -uroot -p
```

```sql
CREATE DATABASE test_db;
USE test_db;
CREATE TABLE test_table (id INT, name VARCHAR(100)) ENGINE=ColumnStore;
INSERT INTO test_table VALUES (1, 'Hello ColumnStore!');
SELECT * FROM test_table;
```

## Configuration

### Environment Variables

The `MARIADB_*` variables of the [official image](https://hub.docker.com/_/mariadb) apply, for example `MARIADB_ROOT_PASSWORD` and `MARIADB_AUTO_UPGRADE`.

The example `docker-compose.yaml` reads these from the environment or a `.env` file:

```bash
# Container name and hostname (default: mcs)
MCS=mcs
# Root password (default: C0lumnStore!)
MCS_ROOT_PASSWORD=your_secure_password
```

### Volumes

| Path | Contents |
|---|---|
| `/var/lib/mysql` | MariaDB's data directory |
| `/var/lib/columnstore` | ColumnStore's data |
| `/etc/columnstore` | ColumnStore's configuration (`Columnstore.xml`), changed at runtime and by `mcsSetConfig` |

### Memory

ColumnStore sizes its memory use as shares of the memory it finds, and it reads the host's total memory, not a container limit. By default it takes up to 20% for its block cache (`DBBC NumBlocksPct`) and up to 65% for joins and aggregations (`HashJoin TotalUmMemory`). On a host shared with other services, lower the shares with `mcsSetConfig`, for example:

```bash
docker compose exec mcs mcsSetConfig DBBC NumBlocksPct 10
docker compose exec mcs mcsSetConfig HashJoin TotalUmMemory 15%
docker compose restart
```

The settings are stored in `/etc/columnstore`, so they survive restarts as long as that is a volume.

### Character Set

The plugin's own `columnstore.cnf` sets `character_set_server = utf8` and `collation_server = utf8_general_ci`. That overrides MariaDB's defaults, `utf8mb4` and `utf8mb4_uca1400_ai_ci`, so tables without an explicit character set get `utf8mb3`.

## How It Works

ColumnStore's packages start their daemons through systemd, which a container doesn't have. `entrypoint.sh` does what the systemd units would:

1. Loads the saved BRM (ColumnStore's block resolution manager state), if there is one.
2. Starts the daemons as the `mysql` user, in the order of the units: `workernode`, `controllernode`, `PrimProc`, `WriteEngineServer`, `DMLProc`, `DDLProc`.
3. Runs `dbbuilder 7`, which creates the system catalog on the first start and leaves it alone afterwards.
4. Runs the official image's entrypoint. On the first start, `initdb.sh` registers ColumnStore's functions and system catalog tables in MariaDB, as the package's post-install script would.

On stop, it stops MariaDB first, then the daemons in the reverse order, and saves the BRM. Give it time to do so: the example compose file sets `stop_grace_period: 2m`.

### Logging

The ColumnStore daemons log through syslog only. rsyslog in the container forwards their messages from `info` up to `docker logs`. Debug messages are left out, as ColumnStore logs the start and end of every SQL statement at that level. `rsyslog.conf` includes `/etc/rsyslog.d/*.conf`, so an image built on this one can add them with a file of its own:

```
*.=debug action(type="omfile" file="/proc/1/fd/1" template="docker")
```

`cpimport` also writes a log file per job in `/var/log/mariadb/columnstore/cpimport/`.

## Tools Available

The plugin package's tools, among them:

- `cpimport` - Bulk data loading
- `mcsGetConfig` / `mcsSetConfig` - Read and change `Columnstore.xml`
- `dbrmctl`, `viewtablelock`, `cleartablelock` - Inspect and manage ColumnStore's state

Run `cpimport` as the `mysql` user, so the data files it writes stay owned by the user the daemons run as. Reading from stdin:

```bash
docker compose exec -T -u mysql mcs cpimport test_db test_table -s '\t' < data.tsv
```

Reading from a file inside the container, `cpimport` also needs a working directory the `mysql` user can write to:

```bash
docker compose exec -u mysql -w /tmp mcs cpimport test_db test_table /path/in/container/data.tsv -s '\t'
```

## Credits and Sources

- **[MariaDB ColumnStore](https://mariadb.com/docs/columnstore)** - The columnar storage engine.
- **[MariaDB ColumnStore engine](https://github.com/mariadb-corporation/mariadb-columnstore-engine)** - Its systemd units and install scripts, which the entrypoint follows.
- **[Official MariaDB ColumnStore Docker repository](https://github.com/mariadb-corporation/mariadb-columnstore-docker)** - The previous official images.
- **[MariaDB Official Docker Image](https://hub.docker.com/_/mariadb)** - The base image.

## License

This project is provided as-is for community use. The underlying MariaDB and ColumnStore components maintain their respective licenses.
