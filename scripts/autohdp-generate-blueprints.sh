#!/bin/bash

if [[ -z $1 ]]; then
  echo "Usage: $0 <options> blueprint_base_name"
  echo "Options:
 -n cluster_name
 -r realm
 -k kdc
 -v hdp_version_short
 -a ambari_version_short
 -u kdc_princ
 -p kdc_pass_opt
 -z disable security"  
  exit -1
fi

SECURITY="true"

while getopts "a:n:r:k:u:p:v:zh" opt; do
        case $opt in
                a  ) AMBARI_VERSION_SHORT=${OPTARG};;
                v  ) HDP_VERSION_SHORT=${OPTARG};;
                n  ) CLUSTER_NAME=${OPTARG};;
                e  ) KDC_EXTERNAL="true";;
                r  ) KDC_REALM=${OPTARG};;
                k  ) KDC_HOST=${OPTARG};;
                u  ) KDC_PRINC=${OPTARG};;
                p  ) KDC_PASS=${OPTARG};; 
                z  ) SECURITY="false";;
                h  ) usage; exit 0;;
                \? ) echo "Invalid option: -$OPTARG" >&2; usage; exit 1;;
                :  ) echo "Option -$OPTARG requires an argument." >&2; usage; exit 1;;
                *  ) echo "Unimplemented option: -$OPTARG" >&2; usage; exit 1;;
        esac
done

shift $((OPTIND-1))
if [[ "$1"XX != XX ]]; then BLUEPRINT_BASE="$1"; fi

KDC_PRINC=${KDC_PRINC:-admin/admin}
KDC_PASS=${KDC_PASS:-admin}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# If security is disabled, reset Kerberos info
SECURITY_TYPE="KERBEROS"
if [[ $SECURITY == "false" ]]; then
SECURITY_TYPE="NONE"
fi


#Use the HDP3 Blueprint                       
if [[ "$HDP_VERSION_SHORT" =~ "3" ]]; then    
BLUEPRINT_BASE=${BLUEPRINT_BASE}.hdp3         
fi                                            
                                              

mkdir -p "$DIR/../tmp"
python "$DIR/autohdp-generate-blueprints.py" \
  "$DIR/../blueprints/${BLUEPRINT_BASE}.blueprint" \
  "$DIR/../tmp/${BLUEPRINT_BASE}-${CLUSTER_NAME}.blueprint" \
  "$HDP_VERSION_SHORT" \
  "$SECURITY_TYPE" \
  "$KDC_REALM" \
  "$KDC_HOST" 
 
# Don't override custom values. Available after Ambari 2.4.
if [[ "$AMBARI_VERSION_SHORT" == "2.2" ]]; then
  STRATEGY=ONLY_STACK_DEFAULTS_APPLY
else
  STRATEGY=ALWAYS_APPLY_DONT_OVERRIDE_CUSTOM_VALUES
fi

# Load settings for 16 GB virtual machine
SETTINGS=$(cat "$DIR/../blueprints/${BLUEPRINT_BASE}-16gb.settings" | jq -r '.Configurations[0]')

# Overlay settings if VM > 16 GB
RAMSIZE=$( free -m | grep Mem | awk '{print $2}' )
if [[ $RAMSIZE > 16384 ]]; then
	SETTINGS=$(cat "$DIR/../blueprints/${BLUEPRINT_BASE}-32gb.settings" | jq -r '.Configurations[0]')	
fi

cat > "$DIR/../tmp/${BLUEPRINT_BASE}-${CLUSTER_NAME}.hostmapping" << EOF 
{
  "blueprint":"singlenode",
  "config_recommendation_strategy" : "${STRATEGY}",
  "default_password":"admin",
  "host_groups":[
    {
      "name":"all",
      "hosts":[ { "fqdn":"`hostname -f`" } ]
    }
  ],
  "credentials" : [
     {
       "alias" : "kdc.admin.credential",
       "principal" : "${KDC_PRINC}",
       "key" : "${KDC_PASS}",
       "type" : "TEMPORARY"
     }
    ],
   "security" : {
        "type" : "${SECURITY_TYPE}"
   },
   "configurations": [
	${SETTINGS}
       ]
}
EOF

