#!/bin/bash
set +x

ME=${0##*/}

AMBARIREPOEX="http://public-repo-1.hortonworks.com/ambari/centos7/2.x/updates/2.6.2.2/ambari.repo"
HDPREPOEX="http://public-repo-1.hortonworks.com/HDP/centos7/2.x/updates/2.6.5.0/hdp.repo"
HDPGPLREPOEX="http://public-repo-1.hortonworks.com/HDP-GPL/centos7/2.x/updates/2.6.5.0/hdp.gpl.repo"
LATEST_HDP="2.6"

KNOWN_REPOS=repos/known_repos.txt
ENV_VARIABLES=tmp/variables.sh
PW_LDAP=admin
LOCALREPO="true"
SECURITY="true"
DEVEL="false"
KDC_EXTERNAL="false"

. scripts/functions.sh

function usage(){
  echo "Automates HDP installation on a single node. GA version is selected unless -d is specified."
  echo "Usage: $ME <options> hdp_version
Options:
	hdp_version		Version of HDP you want to install, see repos/known_versions.txt. Can be shortened eg '2.5'.
	-a ambari_repo		URL to Ambari repository. Can be placed in AMBARIREPO variable.
	-b hdp_repo		URL to HDP repository. Can be placed in HDPREPO variable
	-n cluster_name		Name of the cluster. Can be placed in CLUSTERNAME variable
	-e			Use external kerberos realm. The realm and principal must be specified. OpenLDAP will not be installed.
	-r kdc_realm		Optional kerberos realm name
	-k kdc_host		Kerberos KDC host to access external realm
	-u kdc_princ		Kerberos principal to access external realm
	-p kdc_pass		Kerberos password to access external realm
	-s			Skip local repo creation. 
	-d			Use development release.
	-h			displays help
	-z			Disable security

Example: 
	$ME $LATEST_HDP
"
}

if [[ ! $1 =~ ^\-.* ]]; then HDP_VERSION="$1"; shift 1; fi
while getopts "a:b:n:r:k:u:p:esdhz" opt; do
	case $opt in
		a  ) AMBARIREPO=${OPTARG};;
		b  ) HDPREPO=${OPTARG};;
		n  ) CLUSTERNAME=${OPTARG};;
		e  ) KDC_EXTERNAL="true";;
		r  ) KDC_REALM=${OPTARG};;
		k  ) KDC_HOST=${OPTARG};;
		u  ) KDC_PRINC=${OPTARG};;
		p  ) KDC_PASS=${OPTARG};;
		s  ) LOCALREPO="false";;
		d  ) DEVEL="true";;
		z  ) SECURITY="false"; SECURITY_OPT="-z";;
		h  ) usage; exit 0;;
		\? ) echo "Invalid option: -$OPTARG" >&2; usage; exit 1;;
		:  ) echo "Option -$OPTARG requires an argument." >&2; usage; exit 1;;
		*  ) echo "Unimplemented option: -$OPTARG" >&2; usage; exit 1;;
	esac
done

shift $((OPTIND-1))
if [[ "$1"XX != XX ]]; then HDP_VERSION="$1"; fi

# Supplying a version number is required. When using custom repo, specify all four digits.
if [[ "$HDP_VERSION"X == X ]]; then
	echo "Missing HDP version"
	usage
	exit 1
fi

if [[ ! "$HDPREPO"X == X && "$AMBARIREPO"X == X ]]; then
	echo "Warning: HDP Repo provided but no Ambari repo. Latest known GA version of Ambari will be selected."
fi

# Redhat version
OS_VERSION=$( get_os_version )
if [[ "${OS_VERSION}"X == X ]]; then
   echo "Couldn't determine OS or OS not supported. Only CentOS and RHEL v6 or v7 supported.". Aborting.
   exit 1
fi

# input: requested version, can be abbreviated ie 2.5 or 2.5.2
# returns the fully resolved version from the known repo file (latest non-dev ie GA).
function get_full_resolved_version() {
       HDP_VERSION_LOCAL=$1
       if [[ ! -z $1 ]]; then
         cat repos/known_repos.txt \
		| awk "{ if ( match( \$1, /^hdp$/) ) print \$0}" \
		| awk "{ if ( match( \$3, /^${OS_VERSION}$/) ) print \$0}" \
		| awk "{ if ( match( \$6, /^dev$/) && ( \"${DEVEL}\" != \"true\" ) ) {next} else {print \$0}}" \
		| awk "{ if ( match( \$2, /^${HDP_VERSION_LOCAL}/) ) print \$2}"  | sort -V -r | head -1
       fi
}

# input: full hdp version like 2.4.2.0, not abbreviated
function get_hdp_repo(){
	HDP_VERSION_FULL="$1"
	cat repos/known_repos.txt \
		| awk "{ if ( match( \$1, /^hdp$/) ) print \$0}" \
                | awk "{ if ( match( \$3, /^${OS_VERSION}$/) ) print \$0}" \
		| awk "{ if ( match( \$2, /^${HDP_VERSION_FULL}$/) ) print \$2,\$4}"  | sort -V -r | head -1 | awk '{print $2}'
}

function get_hdpgpl_repo(){
        HDP_VERSION_FULL="$1"
        cat repos/known_repos.txt \
		| awk "{ if ( match( \$1, /^hdp-gpl$/) ) print \$0}" \
                | awk "{ if ( match( \$3, /^${OS_VERSION}$/) ) print \$0}" \
                | awk "{ if ( match( \$2, /^${HDP_VERSION_FULL}$/) ) print \$2,\$4}"  | sort -V -r | head -1 | awk '{print $2}'
}

function get_hdp_recommended_ambari(){
	HDP_VERSION_FULL="$1"
        cat repos/known_repos.txt \
                | awk "{ if ( match( \$1, /^hdp$/) ) print \$0}" \
                | awk "{ if ( match( \$3, /^${OS_VERSION}$/) ) print \$0}" \
		| awk "{ if ( match( \$2, /^${HDP_VERSION_FULL}$/) ) print \$2,\$5}"  | sort -V -r | head -1 | awk '{print $2}'
}

function get_hdp_recommended_utils(){
        HDP_VERSION_FULL="$1"
        cat repos/known_repos.txt \
                | awk "{ if ( match( \$1, /^hdp$/) ) print \$0}" \
                | awk "{ if ( match( \$3, /^${OS_VERSION}$/) ) print \$0}" \
                | awk "{ if ( match( \$2, /^${HDP_VERSION_FULL}$/) ) print \$2,\$6}"  | sort -V -r | head -1 | awk '{print $2}'
}

# input: full hdp version like 2.4.2.0, or empty.
function get_ambari_repo() {
	HDP_VERSION_FULL=$1
	if [[ "${HDP_VERSION_FULL}"X == X ]]; then
		cat repos/known_repos.txt \
                | awk "{ if ( match( \$1, /^ambari$/) ) print \$0}" \
                | awk "{ if ( match( \$3, /^${OS_VERSION}$/) ) print \$0}" \
		| sort -V -r | head -1 | awk '{print $4}'
	else
		AMBARI_VERSION_FULL=$( get_hdp_recommended_ambari $HDP_VERSION_FULL  )
                cat repos/known_repos.txt \
                | awk "{ if ( match( \$1, /^ambari$/) ) print \$0}" \
                | awk "{ if ( match( \$3, /^${OS_VERSION}$/) ) print \$0}" \
		| awk "{ if ( match( \$2, /^${AMBARI_VERSION_FULL}$/) ) print \$2,\$4}"  | sort -V -r | head -1 | awk '{print $2}'
	fi
}

# default for CLUSTERNAME
if [[ "$CLUSTERNAME"X == X ]]; then
	HN=`hostname`
	CLUSTERNAME="${HN%%.*}"
fi

# Resolve to full and short version
if [[ "$HDPREPO"X == X ]]; then
	HDP_VERSION_FULL=$( get_full_resolved_version $HDP_VERSION )
else
	HDP_VERSION_FULL=$HDP_VERSION
fi
HDP_VERSION_SHORT=$( echo $HDP_VERSION_FULL | awk 'match( $0, /[0-9]+\.[0-9]+/, arr ) {print arr[0]}' )

if [[ "$AMBARIREPO"X == X ]]; then
	AMBARI_VERSION_FULL=$( get_hdp_recommended_ambari $HDP_VERSION_FULL  )
fi

HDP_UTILS_VERSION=$( get_hdp_recommended_utils $HDP_VERSION_FULL  )

# Always use a repo manually supplied. Otherwise we get it from our known repo list.
if [[ "$HDPREPO"X == X ]]; then
	HDPREPO=$(get_hdp_repo $HDP_VERSION_FULL)
	if [[ "$HDPREPO"X == X ]]; then	
		echo "Failed to determine HDP repository location. Aborting."
		echo "Check that a repo matches the requested HDP version under repos/known_versions.txt"
	exit 1
	fi
fi

if [[ "$HDPGPLREPO"X == X ]]; then
        HDPGPLREPO=$(get_hdpgpl_repo $HDP_VERSION_FULL)
        if [[ "$HDPGPLREPO"X == X ]]; then
                echo "Failed to determine HDP GPL repository location. Aborting."
                echo "Check that a repo matches the requested HDP-GPL version under repos/known_versions.txt"
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
REALM="${KDC_REALM:-${CLUSTERNAME^^}}"
KDC="${KDC_HOST:-$FQDN}"

yum -y install epel-release


# Prepare blueprints
type jq > /dev/null 2>&1 || yum -y install jq
scripts/autohdp-generate-blueprints.sh -n "${CLUSTERNAME}" -r "$REALM" -k "$KDC" -v "$HDP_VERSION_SHORT" -a "$AMBARI_VERSION_SHORT" -u "$KDC_PRINC" -p "$KDC_PASS" ${SECURITY_OPT} singlenode

# Show values to user and prompt to continue
echo "FQDN=$FQDN"
echo "AMBARIREPO=$AMBARIREPO"
echo "HDPREPO=$HDPREPO"
echo "HDPGPLREPO=$HDPGPLREPO"
echo "CLUSTERNAME=$CLUSTERNAME"
echo "EXTERNAL KDC=$KDC_EXTERNAL"
echo "SECURITY=$SECURITY"
echo "REALM=$REALM"
echo "KDC=$KDC"
echo "CREATE LOCAL REPOSITORY=$LOCALREPO"
echo "OS VERSION=$OS_VERSION"
echo "AMBARI VERSION=$AMBARI_VERSION_FULL"
echo "HDP VERSION SHORT=$HDP_VERSION_SHORT"
if [[ "$KDC_PRINC"XX != XX ]]; then
  echo "EXTERNAL KDC PRINC=$KDC_PRINC"
  echo "EXTERNAL KDC PASS=$KDC_PASS"
fi
# Check the URLs
curl --output /dev/null --silent --head --fail "$AMBARIREPO" || (echo "WARN: issue loading url $AMBARIREPO")
curl --output /dev/null --silent --head --fail "$HDPREPO" || (echo "WARN: issue loading url $HDPREPO.")
curl --output /dev/null --silent --head --fail "$HDPGPLREPO" || (echo "WARN: issue loading url $HDPGPLREPO.")
echo "Blueprints are located under ./tmp"
echo "Press a key to continue"
read -n 1

# Ensure all the tools we need are installed
# WARN: Ambari Infra Solr requires lsof but does not install it as of 2.4.1.0
yum -y install jq pdsh yum-utils wget httpd createrepo expect
service iptables stop
setenforce 0

# Install Kerberos if not external. This is a good test that the system is working.
echo "AUTOHDP: Setting up Kerberos."
scripts/autohdp-kerberos.sh "$REALM" "$KDC" "$KDC_EXTERNAL"
echo "AUTODHP: Kerberos installation complete."

# Only install LDAP if we are using a local KDC
if [[ "$KDC_EXTERNAL" == "false" ]]; then
echo "AUTOHDP: Setting up OpenLDAP."
scripts/autohdp-openldap.sh "$REALM" "$KDC"
echo "AUTOHDP: OpenLDAP installation complete."
# Bind the node to LDAP and KDC for SSH and identity management
echo "AUTOHDP: Joining node to LDAP and KDC domain"
scripts/utils/join-node-ldap-kdc.sh "$REALM" "$KDC"
fi

if [[ "$LOCALREPO" == "true" ]]; then 
# Create local repository for Ambari, HDP and JDK if requested, and configure /etc/yum.repos.d/ambari.repo
# Also creates a local repo for misc files like BerkeleyDB jar for Falcon.
 scripts/autohdp-local-repo.sh -a "$AMBARIREPO" -b "$HDPREPO" -g "$HDPGPLREPO" || exit $?
# Update the variables to point locally
 REPO_SERVER="$FQDN"
 AMBARIREPO="http://${REPO_SERVER}/repo/ambari/ambari.repo"
 HDPREPO="http://${REPO_SERVER}/repo/hdp/hdp.repo" 
 HDPGPLREPO="http://${REPO_SERVER}/repo/hdp-gpl/hdp.gpl.repo"
else
 REPO_SERVER=$( python -c "from urlparse import urlparse
url = urlparse('$HDPREPO')
print url.netloc" )
 wget ${AMBARIREPO} -O /etc/yum.repos.d/ambari.repo
fi

# Generate repo snippets in JSON format for Ambari
scripts/autohdp-ambari-repos.sh "$HDPREPO" "$HDPGPLREPO"

AMBARI_SERVER="$FQDN"

# Persist all variables
# Note that in the case of a local repo, the URLS are now updated.
mkdir -p tmp
cat > "${ENV_VARIABLES}" << EOF
export SECURITY=$SECURITY
export KDC_EXTERNAL=${KDC_EXTERNAL}
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
export HDPGPLREPO=${HDPGPLREPO}
export OS_VERSION=${OS_VERSION}
export KDC_PRINC=$KDC_PRINC
export KDC_PASS=$KDC_PASS
EOF

# If this fails, we are using a public repo with LOCALREPO=false, and ambari will download the necessary files later.
# wget will not redownload if file already exists
mkdir -p /var/lib/ambari-server/resources
wget -nc http://${REPO_SERVER}/resources/jdk-8u122-linux-x64.tar.gz -O /var/lib/ambari-server/resources/jdk-8u122-linux-x64.tar.gz
wget -nc http://${REPO_SERVER}/resources/jce_policy-8.zip -O /var/lib/ambari-server/resources/jce_policy-8.zip

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

# Add BDB jar for Falcon
wget http://search.maven.org/remotecontent?filepath=com/sleepycat/je/5.0.73/je-5.0.73.jar -O /usr/share/je-5.0.73.jar
chmod 644 /usr/share/je-5.0.73.jar
ambari-server setup --jdbc-db=bdb --jdbc-driver=/usr/share/je-5.0.73.jar

# Configure LDAP for Ambari (internal KDC only). This adds the configuration to /etc/ambari-server/conf/ambari.properties
if [[ "$KDC_EXTERNAL" == "false" ]]; then
ambari-server setup-ldap \
--ldap-url=$FQDN:389 \
--ldap-secondary-url=$FQDN:389 \
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
--ldap-sync-username-collisions-behavior=convert \
--ldap-save-settings

# Configure LDAP sync
cat > /etc/cron.hourly/ambari-sync-ldap << EOF
#!/bin/sh
curl -u 'admin:admin' -H 'X-Requested-By: ambari' -X POST -d '[{"Event": {"specs": [{"principal_type": "users", "sync_type": "all"}, {"principal_type": "groups", "sync_type": "all"}]}}]' http://$FQDN:8080/api/v1/ldap_sync_events
EOF
chmod 750 /etc/cron.hourly/ambari-sync-ldap
fi

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

# Ensure that Ambari has fully started
echo "Waiting for Ambari server at http://${AMBARI_SERVER}:8080 to respond to requests."
 while [ `curl -o /dev/null --silent --head --write-out '%{http_code}\n' http://${AMBARI_SERVER}:8080` != 200 ]; do
  echo -n .; sleep 2
done

# TODO: make util version dynamic not static
# Install cluster
scripts/autohdp-install-cluster.sh singlenode "${CLUSTERNAME}" "$HDP_VERSION_SHORT" "$HDP_UTILS_VERSION"

echo ""
echo -e "Ambari is reachable at \033[1mhttp://${AMBARI_SERVER}:8080\033[0m (admin/admin)"
echo "Hint: On Mac, click the Ambari link while pressing cmd."
echo -e "Run \033[1;32mpost-install.sh\033[0m once the cluster is installed."

