# Sourced by docker-entrypoint.sh on the first start, with the temporary server
# running. Does what columnstore-post-install does against MariaDB: registers
# the engine's functions and the system catalog tables.

columnstore_home=$(mktemp -d)
cat > "${columnstore_home}/.my.cnf" <<EOF
[client]
user=root
password=${MARIADB_ROOT_PASSWORD}
socket=${SOCKET}
EOF

mysql_note "ColumnStore: installing functions"
HOME="${columnstore_home}" /usr/sbin/install_mcs_mysql.sh --tmpdir=/var/log/mariadb/columnstore/install
if [ -s /var/log/mariadb/columnstore/install/mysql_install.log ]; then
    mysql_warn "ColumnStore: install_mcs_mysql.sh reported: $(cat /var/log/mariadb/columnstore/install/mysql_install.log)"
fi

mysql_note "ColumnStore: creating the system catalog tables"
docker_process_sql < /usr/share/columnstore/syscatalog_mysql.sql

rm -rf "${columnstore_home}"
unset columnstore_home
