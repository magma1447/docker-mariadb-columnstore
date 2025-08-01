# MariaDB ColumnStore Docker

A Docker setup for MariaDB ColumnStore based on MariaDB 11.8 LTS with ColumnStore 23.10.3 plugin. The [official MariaDB ColumnStore Docker images](https://hub.docker.com/r/mariadb/columnstore) appear to have been abandoned since 2023, so I took matters into my own hands to provide updated containers.

## What This Provides

- **MariaDB 11.8.2 LTS** (latest stable)
- **ColumnStore 23.10.3** (latest community plugin)
- **Proper startup orchestration** with CMAPI cluster management
- **Single-node setup** optimized for development and testing
- **Debian-based** for broader compatibility

## Improvements Over Official Images

The [official MariaDB ColumnStore Docker images](https://hub.docker.com/r/mariadb/columnstore) are based on older versions and haven't been updated since 2023. This project provides:

| Component | Official (2023) | This Project (2025) |
|-----------|-----------------|---------------------|
| MariaDB | 11.1.1 | 11.8.2 (LTS) |
| ColumnStore | 23.02.3 | 23.10.3 |
| Base OS | Rocky Linux 8 | Debian (MariaDB official base) |
| Maintenance | Stagnant | Current |

## CPU Compatibility

This image includes a workaround for older CPU compatibility issues with ColumnStore's Python environment.

### The Problem

Starting with ColumnStore 23.02.4, MariaDB began shipping Python binaries compiled with newer CPU instruction sets that cause "Illegal instruction" errors on older processors. Newest known none working CPU:

- Intel(R) Xeon(R) CPU E5-2620 v2 @ 2.10GHz (from 2013)

### Our Solution

This image uses a hybrid approach:

| Component | Version | Source | Reason |
|-----------|---------|--------|---------|
| MariaDB | 11.8.2 | Official MariaDB 11.8 image | Latest stable features |
| ColumnStore | 23.10.3 | MariaDB plugin packages | Latest community version |
| Python Environment | 3.7.7 | Extracted from ColumnStore 23.02.3 | CPU compatibility |

The Python environment (including all CMAPI dependencies) is extracted from the last known working ColumnStore version (23.02.3) and embedded into the modern container. However module `psutils` was not compatible with the base image's operating system. Therefore we delete that module, and replace it with the one from the apt repositories.

### Remove workaround

You can remove the workaround by removing the sections marked as `TAG: OLD CPU HACK` in the `Dockerfile`.

## Configuration

### Environment Variables

Create a `.env` file to customize settings:

```bash
# Custom root password (default: C0lumnStore!)
MCS_ROOT_PASSWORD=your_secure_password
```

## Quick Start

```bash
# Clone the repository
git clone https://github.com/magma1447/docker-mariadb-columnstore.git
cd docker-mariadb-columnstore

# Start the container (may take a minute for initial startup and ColumnStore initialization)
docker compose up -d

# Connect to MariaDB
docker compose exec mcs mariadb -uroot -p
# Default password: C0lumnStore!

# Test ColumnStore
CREATE DATABASE test_db;
USE test_db;
CREATE TABLE test_table (id INT, name VARCHAR(100)) ENGINE=ColumnStore;
INSERT INTO test_table VALUES (1, 'Hello ColumnStore!');
SELECT * FROM test_table;
```

## Architecture

This setup combines:

1. **MariaDB 11.8** as the base SQL engine
2. **ColumnStore 23.10.3** plugin for columnar analytics
3. **CMAPI** (Cluster Management API) for process orchestration
4. **Proven startup scripts** adapted from the [official ColumnStore Docker repository](https://github.com/mariadb-corporation/mariadb-columnstore-docker)

### Startup Sequence

1. **Initialization** - Sets up MariaDB users and ColumnStore configuration
2. **CMAPI Start** - Launches the cluster management API
3. **Provisioning** - Adds the node to the ColumnStore cluster
4. **Cluster Start** - Starts all ColumnStore processes (controllernode, PrimProc, DMLProc, DDLProc, WriteEngineServer, workernode)
5. **MariaDB Start** - Starts the SQL interface

## Tools Available

The container includes all standard ColumnStore tools:

- `cpimport` - Bulk data loading utility
- `mcs` - ColumnStore cluster management CLI  
- `mcsadmin` - Legacy administrative interface (if available)
- Standard MariaDB tools (`mariadb`, `mariadb-admin`, etc.)

## Monitoring

Check cluster status:
```bash
docker compose exec mcs mcs cluster status
```

View logs:
```bash
docker compose logs -f
```

## Credits and Sources

This project builds upon:

- **[MariaDB ColumnStore](https://mariadb.com/docs/columnstore)** - The columnar storage engine
- **[Official MariaDB ColumnStore Docker Repository](https://github.com/mariadb-corporation/mariadb-columnstore-docker)** - Startup scripts and orchestration logic
- **[MariaDB Official Docker Image](https://hub.docker.com/_/mariadb)** - Base image and MariaDB 11.8
- **MariaDB Community Repository** - ColumnStore 23.10.3 plugin packages

Special thanks to the MariaDB team for making ColumnStore available as a community plugin, even though the official Docker images have become outdated.

## Development Notes

### Technical Approach

1. **Started with MariaDB 11.8** official Docker image
2. **Installed ColumnStore plugin** from MariaDB repositories (`mariadb-plugin-columnstore`, `mariadb-columnstore-cmapi`)
3. **Adapted startup scripts** from the official ColumnStore repository
4. **Fixed path differences** between Rocky Linux and Debian
5. **Added missing provisioning logic** that was crucial for proper cluster initialization

## License

This project is provided as-is for community use. The underlying MariaDB and ColumnStore components maintain their respective licenses.

