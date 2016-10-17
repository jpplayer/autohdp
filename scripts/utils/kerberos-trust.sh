#!/bin/bash

# TODO: remove the need for manually specifying cluster_name
if [[ -z $6 ]]; then
	echo "Usage: kerberos-trust.sh <local_realm> <remote_realm> <remote_realm_host_fqdn> <remote_principal> <remote_pass> <cluster_name>"
	echo "Requires: Local KDC, Remote KDC and Local Ambari up and running"
	echo "remote_principal should be fully qualified including realm"
	exit 1
fi
LOCAL_REALM=$1
REMOTE_REALM=$2
REMOTE_KDC=$3
REMOTE_USER=$4
REMOTE_PASS=$5
CLUSTERNAME=$6

TRUST_PASSWORD="veryinsecure"

OLDPWD="$PWD"
cd ../../tmp

# Update /etc/krb5.conf
sed -i "s/\[realms\]/[realms]\n  ${REMOTE_REALM} = { \n    admin_server = ${REMOTE_KDC} \n    kdc = ${REMOTE_KDC}\n  }\n\n/I" /etc/krb5.conf

# Local
kadmin.local -q "addprinc -pw '${TRUST_PASSWORD}' krbtgt/${LOCAL_REALM}@${REMOTE_REALM}"

# Remote
kadmin -r "${REMOTE_REALM}" -p "${REMOTE_USER}" -w "${REMOTE_PASS}" -q "addprinc -pw '${TRUST_PASSWORD}' krbtgt/${LOCAL_REALM}@${REMOTE_REALM}"

# Call Ambari to adjust auth-to-local
# RULE:[1:$1@$0](.*@FIELD.HORTONWORKS.COM)s/@.*//
/var/lib/ambari-server/resources/scripts/configs.sh get localhost ${CLUSTERNAME} core-site hadoop.security.auth_to_local 
AUTH_TO_LOCAL=$( /var/lib/ambari-server/resources/scripts/configs.sh get localhost ${CLUSTERNAME} core-site | tail -n +2 | xargs -0 -I XX echo '{' XX  '}' | jq -r '.properties."hadoop.security.auth_to_local"' )
AUTH_REPLACE=$( echo 'RULE:[1:$1@$0](.*@'${REMOTE_REALM}')s/@.*// '"$AUTH_TO_LOCAL" | tr ' ' '\n' )
/var/lib/ambari-server/resources/scripts/configs.sh set localhost ${CLUSTERNAME} core-site hadoop.security.auth_to_local "${AUTH_REPLACE}"

cd "$OLD_PWD"
echo "Please restart all services for the trust to take effect: daemons must pick changes to core-site.xml."
