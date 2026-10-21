#!/usr/bin/env bash
set -euo pipefail

FILTER_ID="119978"
LABEL="gw-triaged"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--triage]

Dump untriaged bugs from Jira filter $FILTER_ID.

Options:
  --triage    After listing, add the "$LABEL" label to each ticket (appends, does not overwrite)
  -h, --help  Show this help
EOF
    exit 0
}

triage=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --triage) triage=true; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
done

mapfile -t lines < <(acli jira workitem search --filter "$FILTER_ID" --fields "key,summary" --csv --paginate | tail -n +2)

if [[ ${#lines[@]} -eq 0 ]]; then
    echo "No untriaged bugs found."
    exit 0
fi

keys=()
echo "New tickets:"
for line in "${lines[@]}"; do
    key="${line%%,*}"
    summary="${line#*,}"
    echo "- [$key: $summary](https://redhat.atlassian.net/browse/$key)"
    keys+=("$key")
done

if [[ "$triage" == true ]]; then
    echo ""
    echo "Adding '$LABEL' label to ${#keys[@]} ticket(s)..."
    key_list=$(IFS=,; echo "${keys[*]}")
    acli jira workitem edit --key "$key_list" --labels "$LABEL" --yes
    echo "Done."
fi
