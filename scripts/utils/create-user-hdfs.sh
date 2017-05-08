#!/bin/bash

if [[ -z $1 ]]; then
	echo "Usage: create-user-hdfs.sh <username>"
	echo "Requires: HDFS"
	exit 1
fi
USERNAME=$1
#TODO: Obtain the active Namenode from Ambari
HOSTNAME=`hostname -f`
echo "Creating /user/${USERNAME} folder in HDFS."
su hdfs -c 'princ=$(klist -kt /etc/security/keytabs/hdfs.headless.keytab | grep @ | tail -1 | awk "{print \$4}" ); kinit -kt /etc/security/keytabs/hdfs.headless.keytab $princ'
#su hdfs -c "hdfs dfs -mkdir -p /user/${USERNAME}"
su hdfs -c "curl --negotiate -u : -b ~/cookiejar.txt -c ~/cookiejar.txt -X PUT 'http://${HOSTNAME}:50070/webhdfs/v1/user/${USERNAME}?op=MKDIRS'"
#su hdfs -c "hdfs dfs -chown ${USERNAME} /user/${USERNAME}"
su hdfs -c "curl --negotiate -u : -b ~/cookiejar.txt -c ~/cookiejar.txt -X PUT 'http://${HOSTNAME}:50070/webhdfs/v1/user/${USERNAME}?op=SETOWNER&owner=${USERNAME}'"


