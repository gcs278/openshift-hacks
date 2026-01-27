#!/bin/bash
#
# Setup Kind cluster for parallel canary migration testing
#
# This script can be used in two ways:
# 1. Execute directly: ./setup-kind-with-sail.sh
#    - Runs full setup automatically
#
# 2. Source and call functions:
#    source ./setup-kind-with-sail.sh
#    create_kind_cluster
#    install_sail_operator
#    create_istio_cr
#    ...
#
# This script:
# 1. Creates a Kind cluster with Gateway API CRDs and MetalLB
# 2. Installs Sail operator via Helm
# 3. Creates an Istio CR (openshift-gateway)
# 4. Creates GatewayClass (openshift-default)
# 5. Creates example Gateway with correct labels
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OC_FUNCTIONS="${HOME}/src/github.com/gcs278/openshift-hacks/oc_functions"
GWAPI_INSTALL="${HOME}/src/github.com/gcs278/openshift-hacks/gwapi/install-gwapi-kind.sh"

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

check_prereqs() {
    log_info "Checking prerequisites..."

    local missing=0

    for cmd in kind kubectl helm; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd is not installed"
            missing=1
        fi
    done

    if [ $missing -eq 1 ]; then
        log_error "Please install missing prerequisites"
        exit 1
    fi

    if [ ! -f "$OC_FUNCTIONS" ]; then
        log_error "oc_functions not found at $OC_FUNCTIONS"
        exit 1
    fi

    if [ ! -f "$GWAPI_INSTALL" ]; then
        log_error "install-gwapi-kind.sh not found at $GWAPI_INSTALL"
        exit 1
    fi

    log_info "All prerequisites met"
}

create_kind_cluster() {
    log_info "Creating Kind cluster with Gateway API CRDs and MetalLB..."

    # Source the gwapi install script functions
    source "$GWAPI_INSTALL"

    # Create Kind cluster with basic Gateway API setup (no backend controller)
    # We'll install Sail operator ourselves
    install_gwapi_kind "none"

    # Create OpenShift-style namespaces
    log_info "Creating OpenShift namespaces..."
    kubectl create namespace openshift-ingress --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace openshift-ingress-operator --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace openshift-operators --dry-run=client -o yaml | kubectl apply -f -

    log_info "Kind cluster created successfully"
}

install_sail_operator() {
    log_info "Installing Sail operator..."

    # Source oc_functions to get the installation function
    source "$OC_FUNCTIONS"

    # Install Sail operator in openshift-operators namespace
    SAIL_VERSION="${SAIL_VERSION:-1.27.3}"
    log_info "Using Sail operator version: $SAIL_VERSION"

    # Install using the oc_functions helper
    helm repo add sail-operator https://istio-ecosystem.github.io/sail-operator 2>/dev/null || true
    helm repo update sail-operator

    helm install sail-operator sail-operator/sail-operator \
        --version ${SAIL_VERSION} \
        --namespace openshift-operators \
        --create-namespace \
        --wait \
        --timeout 5m

    log_info "Waiting for Sail operator to be ready..."
    kubectl wait --for=condition=available --timeout=180s deployment/sail-operator -n openshift-operators

    log_info "Sail operator installed successfully"
}

create_istio_cr() {
    log_info "Creating Istio CR (openshift-gateway)..."

    kubectl apply -f "${SCRIPT_DIR}/istio-cr-example.yaml"

    log_info "Waiting for Istio control plane to be ready..."

    # Wait for Istio CR to be ready (check status)
    local max_wait=300
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if kubectl get istio openshift-gateway -o jsonpath='{.status.state}' 2>/dev/null | grep -q "Healthy"; then
            log_info "Istio control plane is healthy"
            break
        fi
        echo -n "."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo ""

    if [ $elapsed -ge $max_wait ]; then
        log_warn "Istio control plane did not become healthy within ${max_wait}s"
        log_warn "Continuing anyway - check with: kubectl get istio openshift-gateway -o yaml"
    fi

    # Wait for istiod deployment
    log_info "Waiting for istiod deployment..."
    kubectl wait --for=condition=available --timeout=180s deployment/istiod -n openshift-ingress 2>/dev/null || {
        log_warn "istiod deployment not ready yet"
        kubectl get pods -n openshift-ingress
    }

    log_info "Istio CR created successfully"
}

create_gatewayclass() {
    log_info "Creating GatewayClass (openshift-default)..."

    kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: openshift-default
spec:
  controllerName: openshift.io/gateway-controller/v1
EOF

    log_info "GatewayClass created successfully"
}

create_example_gateway() {
    log_info "Creating example Gateway and test application..."

    kubectl apply -f "${SCRIPT_DIR}/gateway-example.yaml"

    log_info "Waiting for Gateway to be ready..."
    sleep 10

    # Wait for Gateway to be programmed
    local max_wait=60
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        if kubectl get gateway test-gateway -n openshift-ingress -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null | grep -q "True"; then
            log_info "Gateway is programmed"
            break
        fi
        echo -n "."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo ""

    if [ $elapsed -ge $max_wait ]; then
        log_warn "Gateway did not become programmed within ${max_wait}s"
    fi

    log_info "Example Gateway created successfully"
}

verify_setup() {
    log_info "Verifying setup..."

    echo ""
    echo "=== Sail Operator ==="
    kubectl get pods -n openshift-operators

    echo ""
    echo "=== Istio CR ==="
    kubectl get istio -A

    echo ""
    echo "=== Istio Control Plane ==="
    kubectl get pods -n openshift-ingress -l app=istiod

    echo ""
    echo "=== GatewayClass ==="
    kubectl get gatewayclass

    echo ""
    echo "=== Gateways ==="
    kubectl get gateways -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.gatewayClassName,REV:.metadata.labels.istio\.io/rev,PROGRAMMED:.status.conditions[?(@.type=="Programmed")].status'

    echo ""
    echo "=== Gateway Proxy Deployments ==="
    kubectl get deployments -n openshift-ingress -l gateway.networking.k8s.io/gateway-name

    echo ""
    log_info "Setup verification complete!"
}

print_summary() {
    echo ""
    echo "=========================================="
    echo "  Kind Cluster Setup Complete!"
    echo "=========================================="
    echo ""
    echo "Your Kind cluster is now ready for migration testing with:"
    echo "  - Sail operator installed in openshift-operators namespace"
    echo "  - Istio CR 'openshift-gateway' managing control plane in openshift-ingress"
    echo "  - GatewayClass 'openshift-default' created"
    echo "  - Example Gateway 'test-gateway' with istio.io/rev=openshift-gateway label"
    echo ""
    echo "Next steps:"
    echo "  1. Test the current setup:"
    echo "     kubectl get gateway test-gateway -n openshift-ingress -o yaml"
    echo ""
    echo "  2. Run the migration:"
    echo "     ${SCRIPT_DIR}/migrate-canary.sh"
    echo ""
    echo "  3. Clean up when done:"
    echo "     kind delete cluster --name kind"
    echo ""
}

usage() {
    cat <<EOF
Usage: $0 [function_name]

Run the full setup (when no arguments given):
    $0

Or call a specific function:
    $0 check_prereqs
    $0 create_kind_cluster
    $0 install_sail_operator
    $0 create_istio_cr
    $0 create_gatewayclass
    $0 create_example_gateway
    $0 verify_setup

Or source and call functions directly:
    source $0
    create_kind_cluster
    install_sail_operator

Available functions:
    check_prereqs          - Verify prerequisites are installed
    create_kind_cluster    - Create Kind cluster with Gateway API CRDs and MetalLB
    install_sail_operator  - Install Sail operator via Helm
    create_istio_cr        - Create Istio CR (openshift-gateway)
    create_gatewayclass    - Create GatewayClass (openshift-default)
    create_example_gateway - Create example Gateway and test application
    verify_setup           - Verify the setup
    print_summary          - Print setup summary
EOF
}

main() {
    set -euo pipefail

    log_info "Starting Kind cluster setup for parallel canary migration testing"

    check_prereqs
    create_kind_cluster
    install_sail_operator
    create_istio_cr
    create_gatewayclass
    create_example_gateway
    verify_setup
    print_summary
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # If a function name is provided, call it directly
    if [ $# -gt 0 ]; then
        if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
            usage
            exit 0
        fi

        # Check if the function exists
        if declare -f "$1" > /dev/null; then
            "$@"
        else
            log_error "Unknown function: $1"
            echo ""
            usage
            exit 1
        fi
    else
        # No arguments, run full setup
        main
    fi
fi
