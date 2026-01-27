#!/bin/bash
set -euo pipefail

# This script deploys the Istio bookinfo demo application to demonstrate
# service mesh capabilities using the openshift-gateway revision.

# Configuration
NAMESPACE="${NAMESPACE:-bookinfo}"
ISTIO_REVISION="${ISTIO_REVISION:-openshift-gateway}"
ISTIO_BRANCH="${ISTIO_BRANCH:-master}"
ISTIO_REPO_BASE="https://raw.githubusercontent.com/istio/istio/${ISTIO_BRANCH}/samples/bookinfo"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}==>${NC} $*"
}

warn() {
    echo -e "${YELLOW}Warning:${NC} $*"
}

error() {
    echo -e "${RED}Error:${NC} $*" >&2
}

success() {
    echo -e "${GREEN}$*${NC}"
}

check_requirements() {
    info "Checking required tools..."

    local missing_tools=()

    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi

    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi

    if ! command -v oc &> /dev/null; then
        warn "oc CLI not found, will use kubectl"
    fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    info "Checking cluster connectivity..."
    if ! kubectl cluster-info &>/dev/null; then
        error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    info "All requirements met"
}

create_namespace() {
    info "Creating namespace '${NAMESPACE}'..."

    if kubectl get namespace "${NAMESPACE}" &>/dev/null; then
        warn "Namespace '${NAMESPACE}' already exists"
    else
        kubectl create namespace "${NAMESPACE}"
        success "Namespace created"
    fi

    # Configure PodSecurity for the namespace
    # Note: Istio sidecar injection requires 'privileged' level due to istio-init container
    # which needs NET_ADMIN/NET_RAW capabilities and runs as root
    info "Configuring PodSecurity to 'privileged' for Istio compatibility..."
    if [[ "${NAMESPACE}" != "openshift-ingress" ]]; then
      kubectl label namespace "${NAMESPACE}" pod-security.kubernetes.io/enforce=privileged --overwrite
      kubectl label namespace "${NAMESPACE}" pod-security.kubernetes.io/warn=privileged --overwrite
      kubectl label namespace "${NAMESPACE}" pod-security.kubernetes.io/audit=privileged --overwrite
    fi
    # Label namespace for Istio injection with specific revision
    info "Labeling namespace for Istio sidecar injection (revision: ${ISTIO_REVISION})..."
    kubectl label namespace "${NAMESPACE}" "istio.io/rev=${ISTIO_REVISION}" --overwrite
    # Remove the default istio-injection label to avoid conflicts with revision-based injection
    kubectl label namespace "${NAMESPACE}" "istio-injection-" --overwrite 2>/dev/null || true
   
    success "Namespace configured for service mesh"
}

deploy_bookinfo_app() {
    info "Deploying bookinfo application from Istio repository..."

    local bookinfo_url="${ISTIO_REPO_BASE}/platform/kube/bookinfo.yaml"

    info "Downloading from: ${bookinfo_url}"
    if ! curl -sfL "${bookinfo_url}" | kubectl apply -n "${NAMESPACE}" -f -; then
        error "Failed to deploy bookinfo application"
        exit 1
    fi

    success "Bookinfo application deployed"
}

configure_openshift_security() {
    # Check if we're on OpenShift
    if ! command -v oc &> /dev/null; then
        info "Not running on OpenShift, skipping SCC configuration"
        return 0
    fi

    info "Detected OpenShift - configuring Security Context Constraints..."

    # List of service accounts created by bookinfo
    local service_accounts=(
        "bookinfo-details"
        "bookinfo-productpage"
        "bookinfo-ratings"
        "bookinfo-reviews"
    )

    # Grant privileged SCC to service accounts
    # This is required for Istio sidecar injection because istio-init container needs:
    # - NET_ADMIN and NET_RAW capabilities
    # - Run as root (UID 0)
    for sa in "${service_accounts[@]}"; do
        info "Granting privileged SCC to service account: ${sa}"
        if ! oc adm policy add-scc-to-user privileged -z "${sa}" -n "${NAMESPACE}" &>/dev/null; then
            warn "Failed to grant privileged SCC to ${sa} (may already exist)"
        fi
    done

    # Restart deployments to apply the new SCC permissions
    # Pods created before SCC was granted will fail, so we need to recreate them
    info "Restarting deployments to apply SCC permissions..."
    local deployments=$(kubectl get deployments -n "${NAMESPACE}" -o name 2>/dev/null)
    if [ -n "${deployments}" ]; then
        for deployment in ${deployments}; do
            kubectl rollout restart "${deployment}" -n "${NAMESPACE}" &>/dev/null || warn "Failed to restart ${deployment}"
        done
        success "Deployments restarted"
    else
        warn "No deployments found to restart"
    fi

    success "OpenShift security configured"
}

wait_for_pods() {
    info "Waiting for pods to be ready..."
    kubectl wait --for=condition=Ready pods --all -n "${NAMESPACE}" --timeout=300s
    success "All pods are ready"
}

create_gateway() {
    info "Creating Istio Gateway and VirtualService from Istio repository..."

    local gateway_url="${ISTIO_REPO_BASE}/networking/bookinfo-gateway.yaml"

    info "Downloading from: ${gateway_url}"
    if ! curl -sfL "${gateway_url}" | kubectl apply -n "${NAMESPACE}" -f -; then
        error "Failed to create gateway and virtual service"
        exit 1
    fi

    success "Gateway and VirtualService created"
}


create_destination_rules() {
    info "Creating DestinationRules from Istio repository..."

    local destination_rules_url="${ISTIO_REPO_BASE}/networking/destination-rule-all.yaml"

    info "Downloading from: ${destination_rules_url}"
    if ! curl -sfL "${destination_rules_url}" | kubectl apply -n "${NAMESPACE}" -f -; then
        error "Failed to create destination rules"
        exit 1
    fi

    success "DestinationRules created"
}

print_status() {
    echo ""
    echo "=========================================="
    success "Bookinfo Demo Deployed Successfully!"
    echo "=========================================="
    echo ""
    echo "Namespace: ${NAMESPACE}"
    echo "Istio Revision: ${ISTIO_REVISION}"
    echo ""
    info "Application Components:"
    kubectl get pods -n "${NAMESPACE}"
    echo ""
    info "Services:"
    kubectl get svc -n "${NAMESPACE}"
    echo ""
}

print_access_info() {
    echo ""
    echo "=========================================="
    info "How to Access the Application"
    echo "=========================================="
    echo ""

    # Try to get ingress gateway info
    if kubectl get svc -n openshift-ingress istio-ingressgateway &>/dev/null; then
        echo "Getting ingress gateway information..."
        echo ""
        echo "Run the following commands to access the application:"
        echo ""
        echo -e "${YELLOW}# Get the ingress host and port${NC}"
        echo "export INGRESS_HOST=\$(kubectl get svc -n openshift-ingress istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
        echo "export INGRESS_PORT=\$(kubectl get svc -n openshift-ingress istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name==\"http2\")].port}')"
        echo ""
        echo -e "${YELLOW}# Access the productpage${NC}"
        echo "curl -s http://\${INGRESS_HOST}:\${INGRESS_PORT}/productpage | grep -o \"<title>.*</title>\""
        echo ""
        echo "Or open in browser:"
        echo "echo \"http://\${INGRESS_HOST}:\${INGRESS_PORT}/productpage\""
    else
        echo "To access the application, you'll need to:"
        echo ""
        echo "1. Expose the productpage service via a route or port-forward:"
        echo ""
        echo -e "${YELLOW}# Option 1: Port-forward (for testing)${NC}"
        echo "kubectl port-forward -n ${NAMESPACE} svc/productpage 9080:9080"
        echo "# Then access: http://localhost:9080/productpage"
        echo ""
        echo -e "${YELLOW}# Option 2: Create an OpenShift route${NC}"
        echo "oc expose svc productpage -n ${NAMESPACE}"
        echo "oc get route productpage -n ${NAMESPACE}"
    fi
    echo ""
}

print_demo_scenarios() {
    echo ""
    echo "=========================================="
    info "Demo Scenarios"
    echo "=========================================="
    echo ""
    echo "1. Traffic Routing - Route all traffic to reviews v1 (no stars):"
    echo ""
    echo "kubectl apply -n ${NAMESPACE} -f - <<EOF"
    echo "apiVersion: networking.istio.io/v1beta1"
    echo "kind: VirtualService"
    echo "metadata:"
    echo "  name: reviews"
    echo "spec:"
    echo "  hosts:"
    echo "  - reviews"
    echo "  http:"
    echo "  - route:"
    echo "    - destination:"
    echo "        host: reviews"
    echo "        subset: v1"
    echo "EOF"
    echo ""
    echo "2. Traffic Splitting - 50% to v1, 50% to v3 (red stars):"
    echo ""
    echo "kubectl apply -n ${NAMESPACE} -f - <<EOF"
    echo "apiVersion: networking.istio.io/v1beta1"
    echo "kind: VirtualService"
    echo "metadata:"
    echo "  name: reviews"
    echo "spec:"
    echo "  hosts:"
    echo "  - reviews"
    echo "  http:"
    echo "  - route:"
    echo "    - destination:"
    echo "        host: reviews"
    echo "        subset: v1"
    echo "      weight: 50"
    echo "    - destination:"
    echo "        host: reviews"
    echo "        subset: v3"
    echo "      weight: 50"
    echo "EOF"
    echo ""
    echo "3. Fault Injection - Inject 5s delay for user 'jason':"
    echo ""
    echo "kubectl apply -n ${NAMESPACE} -f - <<EOF"
    echo "apiVersion: networking.istio.io/v1beta1"
    echo "kind: VirtualService"
    echo "metadata:"
    echo "  name: reviews"
    echo "spec:"
    echo "  hosts:"
    echo "  - reviews"
    echo "  http:"
    echo "  - match:"
    echo "    - headers:"
    echo "        end-user:"
    echo "          exact: jason"
    echo "    fault:"
    echo "      delay:"
    echo "        percentage:"
    echo "          value: 100.0"
    echo "        fixedDelay: 5s"
    echo "    route:"
    echo "    - destination:"
    echo "        host: reviews"
    echo "        subset: v1"
    echo "  - route:"
    echo "    - destination:"
    echo "        host: reviews"
    echo "        subset: v1"
    echo "EOF"
    echo ""
}

print_cleanup() {
    echo ""
    echo "=========================================="
    info "Cleanup"
    echo "=========================================="
    echo ""
    echo "To remove the bookinfo demo:"
    echo ""
    echo -e "${YELLOW}kubectl delete namespace ${NAMESPACE}${NC}"
    echo ""
}

# Main execution
main() {
    echo ""
    success "Istio Bookinfo Demo Setup"
    echo "=========================================="
    echo ""

    check_requirements
    create_namespace
    deploy_bookinfo_app
#    if [[ "${NAMESPACE}" != "openshift-ingress" ]]; then
      configure_openshift_security
#    fi
    wait_for_pods
    create_gateway
    create_destination_rules

    print_status
    print_access_info
    print_demo_scenarios
    print_cleanup
}

main "$@"
