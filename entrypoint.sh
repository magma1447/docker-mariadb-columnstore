#!/bin/bash
# Starts the ColumnStore daemons the way the packaged systemd units would,
# then runs the stock MariaDB entrypoint. On SIGTERM, stops MariaDB first and
# then ColumnStore, in the reverse order, saving the BRM on the way out.

set -euo pipefail

LOG_DIR=/var/log/mariadb/columnstore
TMP_DIR=$(mcsGetConfig SystemConfig SystemTempFileDir)

log() {
    echo "[columnstore-entrypoint] $*"
}

as_mysql() {
    gosu mysql "$@"
}

jemalloc() {
    ldconfig -p | grep -m1 libjemalloc | awk '{print $1}'
}

prepare() {
    mkdir -p "${LOG_DIR}"/{archive,corefiles,trace,cpimport,install} \
             "${LOG_DIR}"/data/bulk/{data/import,job,rollback,tmpjob} \
             /var/lib/columnstore/data1/systemFiles/dbrm \
             /var/lib/columnstore/storagemanager \
             "${TMP_DIR}" \
             /var/lock/subsys
    chown -R mysql:mysql "${LOG_DIR}" /etc/columnstore /var/lib/columnstore "${TMP_DIR}"
    chmod 777 /dev/shm

    rm -f /run/rsyslogd.pid
    rsyslogd
}

start_columnstore() {
    # A fresh install has no saved BRM yet, and mcs-loadbrm.py exits 1 on that.
    if [ -e "$(mcsGetConfig SystemConfig DBRMRoot)_current" ]; then
        log "Loading BRM"
        as_mysql /usr/bin/mcs-loadbrm.py no
    else
        log "No saved BRM, starting with an empty one"
    fi

    log "Starting workernode"
    as_mysql env MALLOC_CONF= workernode DBRM_Worker1
    log "Starting controllernode"
    as_mysql env MALLOC_CONF= controllernode
    log "Starting PrimProc"
    as_mysql env MALLOC_CONF= LD_PRELOAD="$(jemalloc)" PrimProc
    log "Starting WriteEngineServer"
    as_mysql env MALLOC_CONF= LD_PRELOAD="$(jemalloc)" WriteEngineServer
    log "Starting DMLProc"
    as_mysql env MALLOC_CONF= DMLProc
    log "Starting DDLProc"
    as_mysql env MALLOC_CONF= DDLProc

    # Creates the system catalog on the first start. Afterwards it finds the
    # catalog and leaves it alone, but exits non-zero; its status file still
    # says OK, so that is what tells success apart.
    log "Running dbbuilder"
    rm -f "${LOG_DIR}/install/dbbuilder.status"
    as_mysql dbbuilder 7 >> "${LOG_DIR}/install/dbbuilder.log" 2>&1 || true
    if ! grep -q '^OK' "${LOG_DIR}/install/dbbuilder.status" 2> /dev/null; then
        log "dbbuilder failed, see ${LOG_DIR}/install/dbbuilder.log"
        exit 1
    fi
}

stop_process() {
    # pgrep and pkill match the kernel's process name, cut at 15 characters.
    local name=${1:0:15}
    local timeout=$2

    pkill -TERM -x "${name}" || return 0
    while pgrep -x "${name}" > /dev/null && [ "${timeout}" -gt 0 ]; do
        sleep 1
        timeout=$((timeout - 1))
    done
    if pgrep -x "${name}" > /dev/null; then
        log "${name} did not stop in time, killing it"
        pkill -KILL -x "${name}" || true
    fi
}

stop_columnstore() {
    log "Stopping ColumnStore"
    stop_process DMLProc 900
    stop_process DDLProc 2
    stop_process WriteEngineServer 20
    stop_process PrimProc 2
    stop_process controllernode "$(mcsGetConfig SystemConfig DBRMTimeout)"
    stop_process workernode 900
    as_mysql /usr/bin/mcs-savebrm.py || log "mcs-savebrm.py failed"
    clearShm > /dev/null 2>&1 || true
}

shutdown() {
    log "Received stop signal"
    if [ -n "${MARIADB_PID:-}" ]; then
        kill -TERM "${MARIADB_PID}" 2> /dev/null || true
        wait "${MARIADB_PID}" || true
    fi
    stop_columnstore
    exit 0
}

if [ "${1:-}" != "mariadbd" ]; then
    exec docker-entrypoint.sh "$@"
fi

prepare
start_columnstore

trap shutdown TERM INT

docker-entrypoint.sh "$@" &
MARIADB_PID=$!

# wait returns early when a trapped signal arrives; shutdown() then takes over.
set +e
wait "${MARIADB_PID}"
STATUS=$?
log "MariaDB exited with status ${STATUS}"
stop_columnstore
exit "${STATUS}"
