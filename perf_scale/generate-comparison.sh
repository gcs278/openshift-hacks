source env.sh
source ../../utils/compare.sh

# Source secrets
SECRETS=secrets.env
if [[ ! -f ${SECRETS} ]]; then
  echo "ERROR: $secrets doesn't exist"
  exit 1
fi
source $SECRETS

BASELINE_UUID=${1}
UUID=${2}
if [[ "$BASELINE_UUID" == "" ]] || [[ "$UUID" == "" ]]; then
  echo "Usage: $(basename $0) BASELINE_UUID UUID"
  exit 1
fi

python3 -m venv pyenv
source pyenv/bin/activate

install_touchstone

compare "${ES_SERVER_BASELINE} ${ES_SERVER}" "${BASELINE_UUID} ${UUID}" ${COMPARISON_CONFIG} true
