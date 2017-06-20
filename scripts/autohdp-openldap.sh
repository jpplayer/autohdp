#!/bin/bash

# Installs OpenLDAP and integrates it with Kerberos (password pass through)

REALM=$1
KDC=$2

PW_LDAP=admin
PW_ADMIN=admin

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
. "$DIR/functions.sh"

if [[ "$REALM"X == X || "$KDC"X == X ]]; then
  echo "Installs OpenLDAP and integrates it with Kerberos (password pass through)"
  echo "Usage: $0 <kerberos realm> <kdc and kadmin fqdn>"
  exit 1
fi

if [[ -f /var/run/openldap/slapd.pid ]]; then
	echo "An OpenLDAP server appears to be running. Aborting."
	exit 0
fi

yum install -y openldap openldap-clients openldap-servers

# Step 1 - Create Root CA

# Step 2 - Initialize ldap
#cp -rf /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
#chown -R ldap:ldap /var/lib/ldap/DB_CONFIG

OS_VERSION=$( get_os_version )
if [[ "$OS_VERSION" == "centos6" ]]; then
service slapd start
chkconfig slapd on
elif [[ "$OS_VERSION" == "centos7" ]]; then
systemctl start slapd
systemctl enable slapd
else
echo "Couldn't determine OS version. Aborting."
exit 1
fi

# Configure logging
mkdir -p /var/log/slapd
chmod 755 /var/log/slapd
chown ldap:ldap /var/log/slapd
sed -i "/local4.*/d" /etc/rsyslog.conf
cat >> /etc/rsyslog.conf << EOF
local4.*                        /var/log/slapd/slapd.log
EOF
cat >> /etc/logrotate.d/slapd << EOF
/var/log/slapd/slapd.log {
    missingok
    notifempty
    sharedscripts
    delaycompress
    rotate 10
    postrotate
        /bin/systemctl reload slapd.service > /dev/null 2>/dev/null || true
    endscript
}
EOF
service rsyslog restart

# Step 3 - Create OpenLDAP admin password
# We use the same password for everything for now. TODO: different password ?
PW_OLC=$(slappasswd -s ${PW_LDAP})
mkdir -p /tmp/ldap
cat > /tmp/ldap/chrootpw.ldif << EOF
dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: ${PW_OLC}
EOF
ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/ldap/chrootpw.ldif

# Step 4 - Import basic schemas
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/core.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif
#ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/misc.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif

# Step 5 - Configure root dn and acls

if [[ "$OS_VERSION" == "centos6" ]]; then

cat > /tmp/ldap/bdb.ldif << EOF
dn: olcDatabase={2}bdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=hadoop,dc=io

dn: olcDatabase={2}bdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=Manager,dc=hadoop,dc=io

dn: olcDatabase={2}bdb,cn=config
changetype: modify
add: olcRootPW
olcRootPW: ${PW_OLC}

dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base="cn=Manager,dc=hadoop,dc=io" read by * none
olcAccess: {1}to attrs=userPassword by self read by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" write by dn.base="cn=Manager,dc=hadoop,dc=io" write by anonymous auth by * none
EOF
ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/ldap/bdb.ldif

elif [[ "$OS_VERSION" == "centos7" ]]; then

cat > /tmp/ldap/hdb.ldif << EOF

dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" read by dn.base="cn=Manager,dc=hadoop,dc=io" read by * none

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=hadoop,dc=io

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=Manager,dc=hadoop,dc=io

dn: olcDatabase={2}hdb,cn=config
changetype: modify
add: olcRootPW
olcRootPW: ${PW_OLC}

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to attrs=userPassword by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" write by dn.base="cn=Manager,dc=hadoop,dc=io" write by self read by anonymous auth by * none
olcAccess: {1}to dn.base="" by * read
olcAccess: {2}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" write  by dn.base="cn=Manager,dc=hadoop,dc=io" write by * read
EOF
ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/ldap/hdb.ldif

firewall-cmd --add-service=ldap --permanent
firewall-cmd --reload

fi

# Step 6 - Create root DN
cat > /tmp/ldap/hadoop.io.ldif << EOF
dn: dc=hadoop,dc=io
objectClass: dcObject
objectClass: organization
dc: hadoop
o : hadoop
EOF

# Use Manager configured above instead of EXTERNAL
ldapadd -f /tmp/ldap/hadoop.io.ldif -D cn=Manager,dc=hadoop,dc=io -w "${PW_LDAP}"

# Step 7 - Create Users and Groups OU.
cat > /tmp/ldap/users-groups-ou.ldif << EOF
dn: ou=users,dc=hadoop,dc=io
objectClass: organizationalUnit
objectClass: top
ou: users

dn: ou=groups,dc=hadoop,dc=io
objectClass: organizationalUnit
objectClass: top
ou: groups
EOF
ldapadd -f /tmp/ldap/users-groups-ou.ldif -D cn=Manager,dc=hadoop,dc=io -w "${PW_LDAP}"

# Step 8 - Create users group. Note that this will overlap with /etc/group.
cat > /tmp/ldap/users.ldif << EOF
dn: cn=users,ou=groups,dc=hadoop,dc=io
objectClass: posixGroup
cn: users
gidNumber: 100
EOF
ldapadd -f /tmp/ldap/users.ldif -D cn=Manager,dc=hadoop,dc=io -w "${PW_LDAP}"

# Step 9 - Configure SASL to obtain passwords from Kerberos.

# Optional step. Ensure that this host has a keytab at /etc/krb5.keytab and domain_realm are properly configured. Should be handled by Kerberos script.
kinit -k 

# Install sasl
yum -y install cyrus-sasl cyrus-sasl-gssapi
cat > /etc/sysconfig/saslauthd << EOF
START=yes
KRB5_KTNAME=/etc/krb5.keytab
SOCKETDIR=/var/run/saslauthd
MECH=kerberos5
EOF
service saslauthd start

# Configure ldap to use sasl
cat > /etc/sasl2/slapd.conf << EOF
keytab: /etc/krb5.keytab
pwcheck_method: saslauthd
EOF
service slapd restart

# Complete. Optional steps now.

# BGIN DISABLED SECTION
# Disable this section: it conflicts with Ambari
# which then starts creating hadoop users with an id > 2000
if false; then

# Create test user
PW_TEST=test
kadmin.local -q "addprinc -pw ${PW_TEST} test@${REALM}"

cat > /tmp/ldap/test.ldif << EOF
dn: uid=test,ou=users,dc=hadoop,dc=io
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: shadowAccount
cn: test
uid: test
uidNumber: 2000
gidNumber: 100
homeDirectory: /home/test
loginShell: /bin/bash
userPassword: {SASL}test@${REALM}
shadowLastChange: 0
shadowMax: 0
shadowWarning: 0
EOF
ldapadd -f /tmp/ldap/test.ldif -D cn=Manager,dc=hadoop,dc=io -w "${PW_LDAP}"

# Verify that SASL and LDAP work.
testsaslauthd -u test@${REALM} -p ${PW_TEST}
ldapsearch -D 'uid=test,ou=users,dc=hadoop,dc=io' -b dc=hadoop,dc=io -w ${PW_TEST}

fi
# END DISABLED SECTION

# DISABLED
if false; then
# Configure local machine to use LDAP for identity but not PAM
# Requires nslcd. To use SSSD, at least one PAM method is required but we disable all.
# nslcd: requires nss-pam-ldapd
# We disable the cache to make it easier to do testing. For production, re-enable.
yum -y install nss-pam-ldapd

authconfig \
--enablelocauthorize \
--enableldap \
--disableldapauth \
--ldapserver=ldap://localhost:389 \
--disableldaptls \
--ldapbasedn=dc=hadoop,dc=io \
--enablerfc2307bis \
--disablemkhomedir \
--disablecache \
--disablecachecreds \
--disablekrb5 \
--update

# DISABLED
# id 'test'
fi

# Clean up: delete test principal and ldap entry
# TODO


