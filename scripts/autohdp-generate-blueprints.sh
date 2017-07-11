#!/bin/bash

if [[ -z $5 ]]; then
  echo "Usage: $0 <blueprint_base_name> <cluster_name> <realm> <kdc> <hdp_version_short> <ambari_version_short> <kdc_princ_opt> <kdc_pass_opt>"  
  exit -1
fi

BLUEPRINT_BASE=$1
CLUSTER_NAME=$2
REALM=$3
KDC=$4
HDP_VERSION_SHORT=$5
AMBARI_VERSION_SHORT=$6
KDC_PRINC=${7:-admin/admin}
KDC_PASS=${8:-admin}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

mkdir -p "$DIR/../tmp"
python "$DIR/autohdp-generate-blueprints.py" \
  "$DIR/../blueprints/${BLUEPRINT_BASE}.blueprint" \
  "$DIR/../tmp/${BLUEPRINT_BASE}-${CLUSTER_NAME}.blueprint" \
  "$REALM" \
  "$KDC" \
  "$HDP_VERSION_SHORT" 

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
        "type" : "KERBEROS"
   },
   "configurations": [
	${SETTINGS}
       ]
}
EOF

