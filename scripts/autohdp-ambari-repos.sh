#!/bin/bash

if [[ -z $1 ]]; then
	echo "Usage: $0 hdp_repo.repo"
	exit 1
fi

HDP_REPO=$1

## Generate repos in json format for Ambari
mkdir -p tmp
cd tmp
curl -s "${HDP_REPO}" -o hdp.repo

# WARNING: This works as long as HDP comes *before* HDP-UTILS
BASE_HDP=$(awk -F= '/^\[*hdp*\]/{f=1} f==1&&/^baseurl/{print $2;exit}' hdp.repo)
BASE_UTILS=$(awk -F= '/^\[*hdp-utils*\]/{f=1} f==1&&/^baseurl/{print $2;exit}' hdp.repo)

cat > hdp.repo.json << EOF
{
 "Repositories": {
    "base_url": "${BASE_HDP}",
    "verify_base_url" : true
  }
}
EOF
cat > hdp-utils.repo.json << EOF
{
 "Repositories": {
    "base_url": "${BASE_UTILS}",
    "verify_base_url" : true
  }
}
EOF

cd ..
