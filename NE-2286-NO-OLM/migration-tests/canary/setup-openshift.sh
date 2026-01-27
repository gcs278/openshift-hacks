#!/bin/bash
#
# Validate OpenShift cluster readiness for parallel canary migration
#
# This script checks that:
# 1. Sail operator is installed
# 2. Istio CR exists
# 3. Gateway API CRDs are installed
# 4. Gateways exist with correct labels
#

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

check_cli() {
    log_info "Checking for oc/kubectl CLI..."

    if command -v oc &> /dev/null; then
        CLI="oc"
        log_info "Using 'oc' CLI"
    elif command -v kubectl &> /dev/null; then
        CLI="kubectl"
        log_info "Using 'kubectl' CLI"
    else
        log_error "Neither 'oc' nor 'kubectl' CLI found"
        exit 1
    fi

    # Check if we're logged in
    if ! $CLI whoami &> /dev/null; then
        log_error "Not logged in to cluster. Please run '$CLI login' first"
        exit 1
    fi

    log_info "Logged in as: $($CLI whoami)"
}

check_helm() {
    log_info "Checking for helm CLI..."

    if ! command -v helm &> /dev/null; then
        log_error "helm CLI not found - required for installing new control plane"
        exit 1
    fi

    log_info "helm CLI found: $(helm version --short)"
}

check_sail_operator() {
    log_info "Checking for Sail operator..."

    if ! $CLI get deployment sail-operator -n openshift-operators &> /dev/null; then
        log_error "Sail operator not found in openshift-operators namespace"
        log_error "Please install it first using:"
        log_error "  source ~/src/github.com/gcs278/openshift-hacks/oc_functions"
        log_error "  oc_ossm_install_sail_operator"
        exit 1
    fi

    # Check if operator is running
    local ready
    ready=$($CLI get deployment sail-operator -n openshift-operators -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

    if [ "$ready" -eq 0 ]; then
        log_error "Sail operator deployment exists but has 0 ready replicas"
        $CLI get deployment sail-operator -n openshift-operators
        exit 1
    fi

    log_info "Sail operator is running with $ready replica(s)"
}

check_istio_cr() {
    log_info "Checking for Istio CR..."

    if ! $CLI get istio openshift-gateway &> /dev/null; then
        log_error "Istio CR 'openshift-gateway' not found"
        log_error "This is the Sail-managed control plane that we'll migrate from"
        log_error "Please create it first or check if it has a different name:"
        log_error "  $CLI get istio -A"
        exit 1
    fi

    local state
    state=$($CLI get istio openshift-gateway -o jsonpath='{.status.state}' 2>/dev/null || echo "Unknown")

    if [ "$state" != "Healthy" ]; then
        log_warn "Istio CR exists but state is: $state (expected: Healthy)"
        log_warn "You may want to fix this before migrating"
    else
        log_info "Istio CR is Healthy"
    fi

    local namespace
    namespace=$($CLI get istio openshift-gateway -o jsonpath='{.spec.namespace}' 2>/dev/null || echo "")

    if [ -z "$namespace" ]; then
        log_error "Could not determine Istio namespace from CR"
        exit 1
    fi

    log_info "Istio control plane namespace: $namespace"

    # Check if istiod is running
    if ! $CLI get deployment istiod -n "$namespace" &> /dev/null; then
        log_error "istiod deployment not found in namespace $namespace"
        exit 1
    fi

    local istiod_ready
    istiod_ready=$($CLI get deployment istiod -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

    if [ "$istiod_ready" -eq 0 ]; then
        log_error "istiod deployment exists but has 0 ready replicas"
        $CLI get deployment istiod -n "$namespace"
        exit 1
    fi

    log_info "istiod is running with $istiod_ready replica(s)"
}

check_gateway_api_crds() {
    log_info "Checking for Gateway API CRDs..."

    local missing=0

    for crd in gatewayclasses.gateway.networking.k8s.io gateways.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io; do
        if ! $CLI get crd $crd &> /dev/null; then
            log_error "CRD $crd not found"
            missing=1
        fi
    done

    if [ $missing -eq 1 ]; then
        log_error "Gateway API CRDs are not installed"
        exit 1
    fi

    log_info "Gateway API CRDs are installed"
}

check_gateways() {
    log_info "Checking for existing Gateways..."

    local gateway_count
    gateway_count=$($CLI get gateways -A --no-headers 2>/dev/null | wc -l)

    if [ "$gateway_count" -eq 0 ]; then
        log_warn "No Gateways found in the cluster"
        log_warn "The migration script will not have anything to migrate"
        log_warn "You may want to create some Gateways first for testing"
    else
        log_info "Found $gateway_count Gateway(s) in the cluster"

        # Check if any have the openshift-gateway revision label
        local sail_gateways
        sail_gateways=$($CLI get gateways -A -o json 2>/dev/null | jq -r '.items[] | select(.metadata.labels."istio.io/rev" == "openshift-gateway") | "\(.metadata.namespace)/\(.metadata.name)"' | wc -l)

        if [ "$sail_gateways" -eq 0 ]; then
            log_warn "No Gateways have istio.io/rev=openshift-gateway label"
            log_warn "These Gateways may not be managed by the Sail-deployed control plane"
        else
            log_info "Found $sail_gateways Gateway(s) with istio.io/rev=openshift-gateway label"
        fi
    fi
}

print_gateway_info() {
    log_info "Current Gateway status:"

    echo ""
    echo "=== Gateways by Namespace ==="
    $CLI get gateways -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.gatewayClassName,REV:.metadata.labels.istio\.io/rev,PROGRAMMED:.status.conditions[?(@.type=="Programmed")].status'

    echo ""
    echo "=== Gateway Proxy Deployments ==="
    # Gateway proxies are typically in the same namespace as the Gateway
    # and labeled with gateway.networking.k8s.io/gateway-name
    for ns in $($CLI get gateways -A -o jsonpath='{.items[*].metadata.namespace}' | tr ' ' '\n' | sort -u); do
        echo ""
        echo "Namespace: $ns"
        $CLI get deployments -n "$ns" -l gateway.networking.k8s.io/gateway-name 2>/dev/null || echo "  No Gateway proxy deployments found"
    done
}

print_summary() {
    echo ""
    echo "=========================================="
    echo "  OpenShift Cluster Validation Complete!"
    echo "=========================================="
    echo ""
    echo "Your cluster is ready for migration with:"
    echo "  - Sail operator: Running"
    echo "  - Istio CR 'openshift-gateway': Exists"
    echo "  - Gateway API CRDs: Installed"
    echo "  - Gateways: Found"
    echo ""
    echo "Next steps:"
    echo "  1. Review your Gateways above"
    echo ""
    echo "  2. Run the migration script:"
    echo "     ${SCRIPT_DIR}/migrate-canary.sh"
    echo ""
    echo "  3. Monitor the migration:"
    echo "     watch '$CLI get gateways -A -o custom-columns=\"NS:.metadata.namespace,NAME:.metadata.name,REV:.metadata.labels.istio\\.io/rev\"'"
    echo ""
}

main() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    log_info "Validating OpenShift cluster for parallel canary migration"

    check_cli
    check_helm
    check_sail_operator
    check_istio_cr
    check_gateway_api_crds
    check_gateways
    print_gateway_info
    print_summary
}

main "$@"
