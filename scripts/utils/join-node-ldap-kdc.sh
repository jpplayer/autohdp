#!/bin/bash

if [[ -z $2 ]]; then
        echo "Usage: $0 kerberos_realm kdc_and_ldap_fqdn ldap_base_optional"
        exit 1
fi
REALM=$1
KDC_LDAP_FQDN=$2
LDAP_BASE=${3:-dc=hadoop,dc=io}

sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
echo -e "PubkeyAuthentication yes\n" >> /etc/ssh/sshd_config
service sshd reload
yum -y install nss-pam-ldapd  sssd pam_ldap pam_krb5 oddjob oddjob-mkhomedir krb5-workstation
service oddjobd start
authconfig \
--enablelocauthorize \
--enableldap \
--disableldapauth \
--ldapserver=ldap://${KDC_LDAP_FQDN}:389 \
--disableldaptls \
--ldapbasedn=${LDAP_BASE} \
--disablerfc2307bis \
--enablemkhomedir \
--enablecache \
--enablecachecreds \
--enablekrb5 --krb5realm ${REALM} --krb5kdc ${KDC_LDAP_FQDN} --krb5adminserver ${KDC_LDAP_FQDN} \
--update


