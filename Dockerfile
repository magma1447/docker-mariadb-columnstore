FROM mariadb:13.0

# The ColumnStore engine and its tools (cpimport, mcsSetConfig, ...) come from
# MariaDB's own repository, which the base image already has configured.
# rsyslog: the ColumnStore daemons log through syslog only; rsyslog.conf
# forwards that to docker logs.
# The mysql symlink: install_mcs_mysql.sh still calls /usr/bin/mysql.
# debian.cnf: left behind by the package install, root-only, and preferred by
# install_mcs_mysql.sh over the credentials the init script gives it.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        mariadb-plugin-columnstore \
        procps \
        rsyslog \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/rsyslog.d/* \
    && ln -s mariadb /usr/bin/mysql \
    && rm -f /etc/mysql/debian.cnf

COPY rsyslog.conf /etc/rsyslog.conf
COPY entrypoint.sh /usr/local/bin/columnstore-entrypoint.sh
COPY initdb.sh /docker-entrypoint-initdb.d/columnstore.sh

ENTRYPOINT ["/usr/local/bin/columnstore-entrypoint.sh"]
CMD ["mariadbd"]
