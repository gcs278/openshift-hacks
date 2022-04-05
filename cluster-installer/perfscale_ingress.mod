#!/bin/bash
set -e

if [[ ! -f "$1" ]]; then
  echo "ERROR: Need at least 1 argument install-config.yaml"
  exit 1
fi

INSTALL_CONFIG="$1"

# Update the number of worker replicas
WORKER_REPLICAS=30
YAML=$(python3 -c "import yaml;f=open(\"${INSTALL_CONFIG}\");y=yaml.safe_load(f);y['compute'][0]['replicas'] = $WORKER_REPLICAS; y['compute'][0]['platform']['aws'] = {}; y['compute'][0]['platform']['aws']['type'] = 'm6i.4xlarge'; print(yaml.dump(y, default_flow_style=False))")

# Write back to cluster config
echo "$YAML" > $INSTALL_CONFIG

exit 0
