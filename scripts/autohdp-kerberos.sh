#!/bin/bash

# Installs Kerberos and OpenLDAP
# KDC should be FQDN otherwise the domain_realm section won't be working

REALM=$1
KDC=$2

PW_MASTER=admin
PW_ADMIN=admin

if [[ "$REALM"X == X || "$KDC"X == X ]]; then
  echo "Usage: $0 <kerberos_realm> <kdc_fqdn>"
  exit 1
fi

if [[ -f /var/run/krb5kdc.pid ]]; then
	echo "A KDC already appears to be running. Aborting."
	exit 1
fi

if [[ ! "${KDC}" =~ "." ]]; then
	echo "The KDC doesn't appear to be an FQDN. Please supply an FQDN."
	exit 1
fi

yum -y install krb5-server krb5-workstation rng-tools

cat > /var/kerberos/krb5kdc/kadm5.acl << EOF
*/admin@${REALM}	*
EOF

cat > /var/kerberos/krb5kdc/kdc.conf << EOF
[kdcdefaults]
 kdc_ports = 88
 kdc_tcp_ports = 88

[realms]
 ${REALM} = {
  #master_key_type = aes256-cts
  acl_file = /var/kerberos/krb5kdc/kadm5.acl
  dict_file = /usr/share/dict/words
  admin_keytab = /var/kerberos/krb5kdc/kadm5.keytab
  supported_enctypes = aes256-cts:normal aes128-cts:normal des3-hmac-sha1:normal arcfour-hmac:normal des-hmac-sha1:normal des-cbc-md5:normal des-cbc-crc:normal
 }
EOF

cat > /etc/krb5.conf << EOF
[libdefaults]
  renew_lifetime = 7d
  forwardable = true
  default_realm = ${REALM}
  ticket_lifetime = 24h
  dns_lookup_realm = false
  dns_lookup_kdc = false
  default_ccache_name = /tmp/krb5cc_%{uid}
  #default_tgs_enctypes = aes des3-cbc-sha1 rc4 des-cbc-md5
  #default_tkt_enctypes = aes des3-cbc-sha1 rc4 des-cbc-md5

[logging]
  default = FILE:/var/log/krb5kdc.log
  admin_server = FILE:/var/log/kadmind.log
  kdc = FILE:/var/log/krb5kdc.log

[realms]
  ${REALM} = {
    admin_server = ${KDC}
    kdc = ${KDC}
  }

[domain_realm]
  ${KDC} = ${REALM}

EOF

# Increase entropy
if false; then
cat > /usr/lib/systemd/system/rngd.service << EOF
[Unit]
Description=Hardware RNG Entropy Gatherer Daemon
[Service]
ExecStart=/sbin/rngd -f -u /dev/urandom
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
service rngd start
fi

# Create kerberos realm
kdb5_util create -s -P ${PW_MASTER}
kadmin.local -q "addprinc -pw ${PW_ADMIN} admin/admin"
service krb5kdc start
service kadmin start

# Create principal and keytab for the host itself.
kadmin.local -q "addprinc -randkey host/`hostname -f`@${REALM}"
kadmin.local -q "ktadd -k /etc/krb5.keytab host/`hostname -f`@${REALM}"

