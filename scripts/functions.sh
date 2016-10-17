function get_os_version() {
  NUM=$(cat /etc/redhat-release | awk 'match ($0,/[0-9]/,arr) {print arr[0]}')
  echo "centos$NUM"
}

