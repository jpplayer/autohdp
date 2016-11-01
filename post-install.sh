#!/bin/bash

ENV_VARIABLES=tmp/variables.sh
. ${ENV_VARIABLES}

# Wait for HDFS to be running
# TODO

# Create admin user
scripts/utils/create-user-kdc-ldap.sh admin admin ${REALM} ${PW_LDAP}
scripts/utils/create-user-hdfs.sh admin

# Wait for HBase to be running
# TODO

# Init phoenix and allow the admin user full control over hbase
echo "Initializing Phoenix"
su hbase -c "kinit -kt /etc/security/keytabs/hbase.headless.keytab hbase-${CLUSTERNAME}@${REALM} && phoenix-sqlline << EOF
EOF"

echo "Adding full privileges to admin user"
su hbase -c "hbase shell -n << EOF
grant 'admin', 'RWCAX'
EOF
"

