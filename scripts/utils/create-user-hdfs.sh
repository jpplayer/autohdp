#!/bin/bash

if [[ -z $1 ]]; then
	echo "Usage: create-user-hdfs.sh <username>"
	echo "Requires: HDFS"
	exit 1
fi
USERNAME=$1
echo "Creating /user/${USERNAME} folder in HDFS."
su hdfs -c "hdfs dfs -mkdir -p /user/${USERNAME}"
su hdfs -c "hdfs dfs -chown ${USERNAME} /user/${USERNAME}"

