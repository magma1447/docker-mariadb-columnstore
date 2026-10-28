# The base image and the source the ColumnStore package is built from must be
# the same MariaDB release, so both come from this one version.
ARG MARIADB_VERSION=13.0.2

# Builds MariaDB's packages, ColumnStore included, from the release's source
# tag with the patches in patches/ applied, the way MariaDB builds its own
# (debian/autobake-deb.sh). The ColumnStore source is the server's submodule,
# so it is the exact ColumnStore commit that release ships.
FROM mariadb:${MARIADB_VERSION} AS build
ARG MARIADB_VERSION

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        devscripts \
        equivs \
        git \
        lsb-release

RUN git clone --depth 1 --branch mariadb-${MARIADB_VERSION} \
        --recurse-submodules --shallow-submodules \
        https://github.com/MariaDB/server.git /build/server

# AUTOBAKE_PREP_CONTROL_RULES_ONLY: only enable ColumnStore in debian/, so the
# build dependencies can be installed before the build.
WORKDIR /build/server
RUN AUTOBAKE_PREP_CONTROL_RULES_ONLY=1 debian/autobake-deb.sh \
    && mk-build-deps --install --remove \
        --tool 'apt-get -y --no-install-recommends' debian/control

COPY patches/ /build/patches/
RUN cd storage/columnstore/columnstore \
    && for PATCH in /build/patches/*.patch; do patch -p1 < "${PATCH}"; done

RUN DEB_BUILD_OPTIONS="parallel=$(nproc)" debian/autobake-deb.sh


FROM mariadb:${MARIADB_VERSION}

# The ColumnStore engine and its tools (cpimport, mcsSetConfig, ...) come from
# the build stage; their dependencies come from MariaDB's own repository, which
# the base image already has configured.
# rsyslog: the ColumnStore daemons log through syslog only; rsyslog.conf
# forwards that to docker logs.
# The mysql symlink: install_mcs_mysql.sh still calls /usr/bin/mysql.
# debian.cnf: left behind by the package install, root-only, and preferred by
# install_mcs_mysql.sh over the credentials the init script gives it.
COPY --from=build /build/mariadb-plugin-columnstore_*.deb /tmp/
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        /tmp/mariadb-plugin-columnstore_*.deb \
        procps \
        rsyslog \
    && rm -rf /var/lib/apt/lists/* /tmp/*.deb \
    && rm -f /etc/rsyslog.d/* \
    && ln -s mariadb /usr/bin/mysql \
    && rm -f /etc/mysql/debian.cnf

COPY rsyslog.conf /etc/rsyslog.conf
COPY entrypoint.sh /usr/local/bin/columnstore-entrypoint.sh
COPY initdb.sh /docker-entrypoint-initdb.d/columnstore.sh

ENTRYPOINT ["/usr/local/bin/columnstore-entrypoint.sh"]
CMD ["mariadbd"]
