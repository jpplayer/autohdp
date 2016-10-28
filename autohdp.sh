#!/bin/bash
# version 0.3
set +x

ME=${0##*/}

AMBARIREPOEX="http://public-repo-1.hortonworks.com/HDP-LABS/Projects/Erie-Preview/ambari/2.4.0.0-4/centos6/ambari.repo"
HDPREPOEX="http://public-repo-1.hortonworks.com/HDP-LABS/Projects/Erie-Preview/2.5.0.0-4/centos6/hdp.repo"

KNOWN_REPOS=repos/known_repos.txt
ENV_VARIABLES=tmp/variables.sh
PW_LDAP=admin
LOCALREPO="true"

. scripts/functions.sh

function usage(){
  echo "Automates HDP installation."
  echo "Usage: $ME hdp_version
Options:
	hdp_version		Version of HDP you want to install, see repos/known_versions.txt. Can be shortened eg '2.5'.
	-a ambari_repo		URL to Ambari repository. Can be placed in AMBARIREPO variable.
	-b hdp_repo		URL to HDP repository. Can be placed in HDPREPO variable.
	-n cluster_name		Name of the cluster. Can be placed in CLUSTERNAME variable.
	-s			Skip local repo creation. 
	-h			displays help

Example: 
	$ME 2.5
"
}

while getopts ":a:b:n:hs" opt; do
	case $opt in
		a  ) AMBARIREPO=${OPTARG};;
		b  ) HDPREPO=${OPTARG};;
		n  ) CLUSTERNAME=${OPTARG};;
		s  ) LOCALREPO="false";;
		h  ) usage; exit 0;;
		\? ) echo "Invalid option: -$OPTARG" >&2; usage; exit 1;;
		:  ) echo "Option -$OPTARG requires an argument." >&2; usage; exit 1;;
		*  ) echo "Unimplemented option: -$OPTARG" >&2; usage; exit 1;;
	esac
done

shift $((OPTIND-1))
HDP_VERSION="$1"

# Supplying a version number is required. When using custom repo, specify the first two digits.
if [[ "$HDP_VERSION"X == X ]]; then
	usage
	exit 1
fi

if [[ ! "$HDPREPO"X == X && "$AMBARIREPO"X == X ]]; then
	echo "Warning: HDP Repo provided but no Ambari repo. Latest known version of Ambari will be selected."
fi

# Redhat version
OS_VERSION=$( get_os_version )
if [[ "${OS_VERSION}"X == X ]]; then
   echo "Couldn't determine OS". Aborting.
   exit 1
fi

# input: requested version, can be abbreviated ie 2.5 or 2.5.2
# returns the fully resolved version from the known repo file (latest).
function get_full_resolved_version() {
       HDP_VERSION_LOCAL=$1
       if [[ ! -z $1 ]]; then
         grep hdp repos/known_repos.txt \
		| awk "{ if ( match( \$3, /^${OS_VERSION}$/) ) print \$0}" \
		| awk "{ if ( match( \$2, /^${HDP_VERSION_LOCAL}/) ) print \$2}"  | sort -V -r | head -1
       fi
}

# input: full hdp version like 2.4.2.0, not abbreviated
function get_hdp_repo(){
	HDP_VERSION_FULL=$1
	grep hdp repos/known_repos.txt \
                | awk "{ if ( match( \$3, /^${OS_VERSION}$/) ) print \$0}" \
		| awk "{ if ( match( \$2, /^${HDP_VERSION_FULL}$/) ) print \$2,\$4}"  | sort -V -r | head -1 | awk '{print $2}'
}

function get_hdp_recommended_ambari(){
	HDP_VERSION_FULL="$1"
	grep hdp repos/known_repos.txt \
                | awk "{ if ( match( \$3, /^${OS_VERSION}$/) ) print \$0}" \
		| awk "{ if ( match( \$2, /^${HDP_VERSION_FULL}$/) ) print \$2,\$5}"  | sort -V -r | head -1 | awk '{print $2}'
}

# input: full hdp version like 2.4.2.0, or empty.
function get_ambari_repo() {
	HDP_VERSION_FULL=$1
	if [[ "${HDP_VERSION_FULL}"X == X ]]; then
		grep ambari repos/known_repos.txt \
                | awk "{ if ( match( \$3, /^${OS_VERSION}$/) ) print \$0}" \
		| sort -V -r | head -1 | awk '{print $4}'
	else
		AMBARI_VERSION_FULL=$( get_hdp_recommended_ambari $HDP_VERSION_FULL  )
		grep ambari repos/known_repos.txt \
                | awk "{ if ( match( \$3, /^${OS_VERSION}$/) ) print \$0}" \
		| awk "{ if ( match( \$2, /^${AMBARI_VERSION_FULL}$/) ) print \$2,\$4}"  | sort -V -r | head -1 | awk '{print $2}'
	fi
}

# default for CLUSTERNAME
if [[ "$CLUSTERNAME"X == X ]]; then
	CLUSTERNAME=`hostname`
fi

# Resolve to full and short version
HDP_VERSION_FULL=$( get_full_resolved_version $HDP_VERSION )
HDP_VERSION_SHORT=$( echo $HDP_VERSION_FULL | awk 'match( $0, /[0-9]+\.[0-9]+/, arr ) {print arr[0]}' )
AMBARI_VERSION_FULL=$( get_hdp_recommended_ambari $HDP_VERSION_FULL  )

# Always use a repo manually supplied. Otherwise we get it from our known repo list.
if [[ "$HDPREPO"X == X ]]; then
	HDPREPO=$(get_hdp_repo $HDP_VERSION_FULL)
	if [[ "$HDPREPO"X == X ]]; then	
		echo "Failed to determine HDP repository location. Aborting."
		echo "Check that a repo matches the requested HDP version under repos/known_versions.txt"
	exit 1
	fi
fi

if [[ "$AMBARIREPO"X == X ]]; then
	# obtain the recommended Ambari version for the given HDP release.
	# if HDP_VERSION is empty, we use the latest known ambari version.
	AMBARIREPO=$(get_ambari_repo $HDP_VERSION_FULL)
fi

# Check that the node has an FQDN
FQDN=$(hostname -f)  || (echo "Error: this host is not configured with an fqdn" && exit 1)

# Kerberos
REALM="${CLUSTERNAME^^}"
KDC="$FQDN"

# Show values to user and prompt to continue
echo "FQDN=$FQDN"
echo "AMBARIREPO=$AMBARIREPO"
echo "HDPREPO=$HDPREPO"
echo "CLUSTERNAME=$CLUSTERNAME"
echo "REALM=$REALM"
echo "CREATE LOCAL REPOSITORY=$LOCALREPO"
echo "OS VERSION=$OS_VERSION"
echo "Press a key to continue"
read -n 1

# Ensure all the tools we need are installed
# WARN: Ambari Infra Solr requires lsof but does not install it as of 2.4.1.0
yum -y install epel-release
yum -y install jq pdsh yum-utils wget httpd createrepo expect
service iptables stop
setenforce 0

# Install Kerberos. This is a good test that the system is working.
scripts/autohdp-kerberos.sh "$REALM" "$KDC" 
scripts/autohdp-openldap.sh "$REALM" "$KDC"

if [[ "$LOCALREPO" == "true" ]]; then 
# Create local repository for Ambari, HDP and JDK if requested, and configure /etc/yum.repos.d/ambari.repo
 scripts/autohdp-local-repo.sh -a "$AMBARIREPO" -b "$HDPREPO"
 # Now fill out variables
 REPO_SERVER="$FQDN"
 AMBARIREPO="http://${REPO_SERVER}/repo/ambari/ambari.repo"
 HDPREPO="http://${REPO_SERVER}/repo/hdp.repo" 
else
 REPO_SERVER=$( python -c "from urlparse import urlparse
url = urlparse('$HDPREPO')
print url.netloc" )
 wget ${AMBARIREPO} -O /etc/yum.repos.d/ambari.repo
fi

# Generate repo snippets in JSON format for Ambari
scripts/autohdp-ambari-repos.sh "$HDPREPO"

AMBARI_SERVER="$FQDN"

# Persist all variables
mkdir -p tmp
cat > "${ENV_VARIABLES}" << EOF
export REALM=${REALM}
export KDC=${KDC}
export PW_LDAP=${PW_LDAP}
export CLUSTERNAME=${CLUSTERNAME}
export REPO_SERVER=${REPO_SERVER}
export AMBARI_SERVER=${AMBARI_SERVER}
export AMBARI_VERSION_FULL=${AMBARI_VERSION_FULL}
export HDP_VERSION_SHORT=${HDP_VERSION_SHORT}
export HDP_VERSION_FULL=${HDP_VERSION_FULL}
export AMBARIREPO=${AMBARIREPO}
export HDPREPO=${HDPREPO}
export OS_VERSION=${OS_VERSION}
EOF

# If this fails, we are using a public repo with LOCALREPO=false, and ambari will download the necessary files later.
mkdir -p /var/lib/ambari-server/resources
wget http://${REPO_SERVER}/resources/jdk-8u60-linux-x64.tar.gz -O /var/lib/ambari-server/resources/jdk-8u60-linux-x64.tar.gz
wget http://${REPO_SERVER}/resources/jce_policy-8.zip -O /var/lib/ambari-server/resources/jce_policy-8.zip

# Install Ambari
yum -y install ambari-server
ambari-server setup -s
# This fails so we use expect instead
#ambari-server setup-security --security-option=encrypt-password --master-key=admin --master-key-persist=true
# Also fails. Skip for now. To use, change cluster template to "type" : "PERSISTED" 
if false; then
expect << EOF
spawn ambari-server setup-security
expect "Enter choice, (1-5): "
send "2\r"
expect "Please provide master key for locking the credential store: "
send "admin\r"
expect "Re-enter master key: "
send "admin\r"
expect "(y):"
send "y\r"
EOF
fi

# Configure LDAP for Ambari. This adds the configuration to /etc/ambari-server/conf/ambari.properties
ambari-server setup-ldap \
--ldap-url=localhost:389 \
--ldap-secondary-url=localhost:389 \
--ldap-ssl=false \
--ldap-user-attr=uid \
--ldap-user-class=posixAccount \
--ldap-base-dn=dc=hadoop,dc=io \
--ldap-bind-anonym=true \
--ldap-group-class=posixGroup \
--ldap-member-attr=memberUid \
--ldap-group-attr=cn \
--ldap-dn=dn \
--ldap-referral=ignore \
--ldap-bind-anonym=true \
--ldap-save-settings

# Configure LDAP sync
cat > /etc/cron.hourly/ambari-sync-ldap << EOF
#!/bin/sh
curl -u 'admin:admin' -H 'X-Requested-By: ambari' -X POST -d '[{"Event": {"specs": [{"principal_type": "users", "sync_type": "all"}, {"principal_type": "groups", "sync_type": "all"}]}}]' http://localhost:8080/api/v1/ldap_sync_events
EOF
chmod 750 /etc/cron.hourly/ambari-sync-ldap

# Daily backups of ambari database
echo '
BAKFOLDER=/var/lib/backup
DATE=`date +%Y%m%d%H%M`
bak="${BAKFOLDER}/ambari-$DATE"
mkdir -p "${bak}"
cp /etc/ambari-server/conf/ambari.properties "$bak/ambari.properties"
cp /var/lib/ambari-server/ambari-env.sh "$bak/ambari-env.sh"

su - postgres -c "pg_dump ambari" > "$bak/ambari.sql"

tar cfz "$bak.tar.gz" "$bak"
rm -rf "$bak"
' > /etc/cron.daily/ambari-backup
chmod 750 /etc/cron.daily/ambari-backup
# Ranger is still rough, needs own script
# Installs mysql, which requires HDP-UTILS
scripts/autohdp-prepare-ranger.sh

# Start ambari
ambari-server start

# Install Agents
yum install ambari-agent -y
sed -i -e "s/hostname=.*/hostname=${AMBARI_SERVER}/" /etc/ambari-agent/conf/ambari-agent.ini
ambari-agent start

# Prepare blueprints
scripts/autohdp-generate-blueprints.sh singlenode "${CLUSTERNAME}" "$REALM" "$KDC" "$HDP_VERSION_SHORT"


# Ensure that Ambari has fully started
echo "Waiting for Ambari server at http://${AMBARI_SERVER}:8080 to respond to requests."
 while [ `curl -o /dev/null --silent --head --write-out '%{http_code}\n' http://${AMBARI_SERVER}:8080` != 200 ]; do
  echo -n .; sleep 2
done

# TODO: make util version dynamic not static
# Install cluster
scripts/autohdp-install-cluster.sh singlenode "${CLUSTERNAME}" "$HDP_VERSION_SHORT" "1.1.0.21"

echo ""
echo -e "Ambari is reachable at \033[1mhttp://${AMBARI_SERVER}:8080\033[0m"
echo "Hint: On Mac, click the Ambari link while pressing cmd."
echo -e "Run \033[1;32mpost-install.sh\033[0m once the cluster is installed."

