#!/bin/bash
# version 0.1

# Creates a local repository

ME=${0##*/}

REPO_SERVER=`hostname -f`

AMBARIREPOEX="http://public-repo-1.hortonworks.com/HDP-LABS/Projects/Erie-Preview/ambari/2.4.0.0-4/centos6/ambari.repo"
HDPREPOEX="http://public-repo-1.hortonworks.com/HDP-LABS/Projects/Erie-Preview/2.5.0.0-4/centos6/hdp.repo"

function usage(){
  echo "Create a local repository to serve Ambari and HDP packages."
  echo "Usage: $ME -a AMBARIREPO -b HDPREPO
Options:
	-a ambari_repo		URL to Ambari repository
	-b hdp_repo		URL to HDP repository
	-h			displays help

Example: 
	$ME -a $AMBARIREPOEX -b $HDPREPOEX
"
}

# Warning: the following won't ever execute if the script is sourced.
while getopts ":a:b:hs" opt; do
	case $opt in
		a  ) AMBARIREPO=${OPTARG};;
		b  ) HDPREPO=${OPTARG};;
		h  ) usage; exit 0;;
		\? ) echo "Invalid option: -$OPTARG" >&2; usage; exit 1;;
		:  ) echo "Option -$OPTARG requires an argument." >&2; usage; exit 1;;
		*  ) echo "Unimplemented option: -$OPTARG" >&2; usage; exit 1;;
	esac
done

if [[ "$AMBARIREPO"X == X || "$HDPREPO"X == X ]]; then
	usage
	exit 1
fi

echo "Creating a local repository"

# Exit early if a local repo already exists
# TODO: be more thorough in checking
if [[ -f /var/www/html/repo/ambari/ambari.repo ]]; then
	echo "Local repo already exists: /var/www/html/repo/ambari/ambari.repo is present. Skipping."
	exit 0
fi

function checkTools() {
	local missing=""
	if ! type "jq" > /dev/null 2>&1; then
		missing="jq"
	fi
	if ! type "pdsh" > /dev/null 2>&1; then
		missing="$missing pdsh"
	fi
	echo $missing	
}

#missing=$(checkTools)
#if [[ "$missing" != "" ]]; then
#	echo "The following tools are missing: '$missing'". Please install them first.
#	exit 1
#fi

# Ensure all the tools we need are installed
yum -y install epel-release
yum -y install jq pdsh yum-utils wget httpd createrepo


# Download repositories
echo "Downloading repositories"
rm -f /etc/yum.repos.d/ambari.repo
wget "$AMBARIREPO" -O /etc/yum.repos.d/ambari.repo
sed -i -E 's;\[.*?ambari.*?\];[ambari];I' /etc/yum.repos.d/ambari.repo
rm -f /etc/yum.repos.d/hdp.repo
wget "$HDPREPO" -O /etc/yum.repos.d/hdp.repo
sed -i -E 's;\[.*?HDP-[^U].*?\];[hdp];I' /etc/yum.repos.d/hdp.repo
sed -i -E 's;\[.*?HDP-UTILS.*?\];[hdp-utils];I' /etc/yum.repos.d/hdp.repo

OLDPWD="$PWD"
service iptables stop
service httpd start
chkconfig httpd on
mkdir -p /var/www/html/repo
chmod 755 /var/www/html/repo
cd /var/www/html/repo
reposync -r ambari || { echo "Error during reposync. Check yum configuration."; exit 1; }
reposync -r hdp
reposync -r hdp-utils
createrepo ambari
createrepo hdp
createrepo hdp-utils
cd "$OLDPWD"

rm -f /etc/yum.repos.d/hdp.repo

mkdir -p /var/www/html/resources
if [[ ! -f /var/www/html/resources/jdk-8u60-linux-x64.tar.gz ]]; then
  wget http://public-repo-1.hortonworks.com/ARTIFACTS/jdk-8u60-linux-x64.tar.gz -O /var/www/html/resources/jdk-8u60-linux-x64.tar.gz
fi
if [[ ! -f /var/www/html/resources/jce_policy-8.zip ]]; then
  wget http://public-repo-1.hortonworks.com/ARTIFACTS/jce_policy-8.zip -O /var/www/html/resources/jce_policy-8.zip
fi


# Replace ambari.repo
cat > /etc/yum.repos.d/ambari.repo << EOF
[ambari]
name=ambari
gpgcheck=0
baseurl=http://${REPO_SERVER}/repo/ambari
EOF
cp /etc/yum.repos.d/ambari.repo /var/www/html/repo/ambari/ambari.repo

# Create repo file for hdp.
cat > /etc/yum.repos.d/hdp.repo << EOF
[hdp]
name=hdp
gpgcheck=0
baseurl=http://${REPO_SERVER}/repo/hdp

[hdp-utils]
name=hdp-utils
gpgcheck=0
baseurl=http://${REPO_SERVER}/repo/hdp-utils
EOF
cp /etc/yum.repos.d/hdp.repo /var/www/html/repo/hdp.repo


#echo "Use the following URLs for the HDP and HDP-UTILS repositories:"
#echo "http://`hostname -f`/repo/ambari"
#echo "http://`hostname -f`/repo/hdp"
#echo "http://`hostname -f`/repo/hdp-utils"
