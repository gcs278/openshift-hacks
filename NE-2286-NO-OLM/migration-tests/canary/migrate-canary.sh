#!/bin/bash
#
# Parallel Canary Migration Script
#
# Migrates from Sail-managed Istio (istio.io/rev=openshift-gateway) to
# helm-direct Istio (istio.io/rev=helm-direct) using a canary approach.
#
# Steps:
# 1. Deploy new Istio control plane via Helm with different revision
# 2. Relabel each Gateway one-by-one to new revision
# 3. Validate each Gateway after migration
# 4. Delete old Istio CR
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source oc_functions for helper functions
OC_FUNCTIONS="${OC_FUNCTIONS:-${HOME}/src/github.com/gcs278/openshift-hacks/oc_functions}"
if [ -f "$OC_FUNCTIONS" ]; then
    source "$OC_FUNCTIONS"
fi

# Configuration
OLD_REVISION="${OLD_REVISION:-openshift-gateway}"
NEW_REVISION="${NEW_REVISION:-openshift-gateway-helm}"
NEW_CP_NAMESPACE="${NEW_CP_NAMESPACE:-openshift-ingress}"
HELM_VALUES_FILE="${HELM_VALUES_FILE:-${SCRIPT_DIR}/helm-values-new-control-plane.yaml}"

# Istio Helm charts from Sail operator
# NOTE: ISTIO_VERSION will be auto-detected from Sail operator if not set
# We use the charts bundled in the Sail operator repository, not upstream Istio
SAIL_OPERATOR_REPO="${SAIL_OPERATOR_REPO:-https://github.com/istio-ecosystem/sail-operator.git}"
SAIL_OPERATOR_BRANCH="${SAIL_OPERATOR_BRANCH:-main}"
ISTIO_VERSION="${ISTIO_VERSION:-}"  # Will be detected from Sail operator
CHARTS_CACHE_DIR="${CHARTS_CACHE_DIR:-/tmp/sail-operator-charts}"

# Migration behavior
PAUSE_BETWEEN_GATEWAYS="${PAUSE_BETWEEN_GATEWAYS:-10}"  # seconds to wait between Gateway migrations
SKIP_PROMPTS="${SKIP_PROMPTS:-false}"  # set to true to skip confirmation prompts
VALIDATE_GATEWAY_TIMEOUT="${VALIDATE_GATEWAY_TIMEOUT:-120}"  # seconds to wait for Gateway to be ready

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

prompt_continue() {
    if [ "$SKIP_PROMPTS" = "true" ]; then
        return 0
    fi

    echo ""
    read -p "Continue? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Migration cancelled by user"
        exit 0
    fi
}

check_prereqs() {
    log_info "Checking prerequisites..."

    # Check for CLI
    if command -v oc &> /dev/null; then
        CLI="oc"
    elif command -v kubectl &> /dev/null; then
        CLI="kubectl"
    else
        log_error "Neither 'oc' nor 'kubectl' CLI found"
        exit 1
    fi

    # Check for helm
    if ! command -v helm &> /dev/null; then
        log_error "helm CLI not found - required for installing new control plane"
        exit 1
    fi

    # Check for helm values file
    if [ ! -f "$HELM_VALUES_FILE" ]; then
        log_error "Helm values file not found: $HELM_VALUES_FILE"
        exit 1
    fi

    log_info "Prerequisites met (CLI: $CLI)"
}

detect_istio_version() {
    log_info "Detecting Istio version from Sail operator..."

    # If ISTIO_VERSION is already set, use it
    if [ -n "$ISTIO_VERSION" ]; then
        log_info "Using explicitly set ISTIO_VERSION: $ISTIO_VERSION"
        return 0
    fi

    # Try to get version from the Istio CR status
    local version_from_cr
    version_from_cr=$($CLI get istio "$OLD_REVISION" -o jsonpath='{.status.revisions.inUse[0]}' 2>/dev/null || echo "")

    if [ -n "$version_from_cr" ]; then
        # The version from CR might be like "1-24-2" or "1.24.2", normalize it
        ISTIO_VERSION=$(echo "$version_from_cr" | sed 's/-/./g')
        log_info "Detected Istio version from CR status: $ISTIO_VERSION"
        return 0
    fi

    # Try to get version from istiod deployment
    local old_namespace
    old_namespace=$($CLI get istio "$OLD_REVISION" -o jsonpath='{.spec.namespace}' 2>/dev/null || echo "openshift-ingress")

    local istiod_version
    istiod_version=$($CLI get deployment istiod -n "$old_namespace" -o jsonpath='{.spec.template.spec.containers[?(@.name=="discovery")].image}' 2>/dev/null | grep -oP 'istio/pilot:\K[0-9]+\.[0-9]+\.[0-9]+' || echo "")

    if [ -n "$istiod_version" ]; then
        ISTIO_VERSION="$istiod_version"
        log_info "Detected Istio version from istiod deployment: $ISTIO_VERSION"
        return 0
    fi

    # Try to get version from Sail operator
    # In Kind: deployment name is "sail-operator"
    # In OpenShift: deployment name is "servicemesh-operator3"
    local sail_deployment
    if $CLI get deployment sail-operator -n openshift-operators &> /dev/null; then
        sail_deployment="sail-operator"
    elif $CLI get deployment servicemesh-operator3 -n openshift-operators &> /dev/null; then
        sail_deployment="servicemesh-operator3"
    else
        log_debug "Sail operator deployment not found (tried: sail-operator, servicemesh-operator3)"
        sail_deployment=""
    fi

    if [ -n "$sail_deployment" ]; then
        local sail_version
        sail_version=$($CLI get deployment $sail_deployment -n openshift-operators -o jsonpath='{.spec.template.spec.containers[?(@.name=="manager")].env[?(@.name=="ISTIO_VERSION")].value}' 2>/dev/null || echo "")

        if [ -n "$sail_version" ]; then
            ISTIO_VERSION="$sail_version"
            log_info "Detected Istio version from Sail operator ($sail_deployment) env: $ISTIO_VERSION"
            return 0
        fi

        # Fallback: Check Sail operator version and map to Istio version
        local sail_chart_version
        sail_chart_version=$($CLI get deployment $sail_deployment -n openshift-operators -o jsonpath='{.metadata.labels.app\.kubernetes\.io/version}' 2>/dev/null || echo "")

        if [ -n "$sail_chart_version" ]; then
            log_info "Detected Sail operator version: $sail_chart_version"

            # Map Sail operator version to Istio version
            # Sail operator 3.0.x typically uses Istio 1.24.x
            case "$sail_chart_version" in
                3.0.*|1.27.*)
                    ISTIO_VERSION="1.24.2"
                    log_info "Mapped Sail operator $sail_chart_version to Istio version: $ISTIO_VERSION"
                    ;;
                *)
                    # Default fallback
                    ISTIO_VERSION="1.24.2"
                    log_warn "Unknown Sail operator version $sail_chart_version, using default Istio version: $ISTIO_VERSION"
                    ;;
            esac
            return 0
        fi
    fi

    # Final fallback if all detection methods failed
    ISTIO_VERSION="1.27.3"
    log_warn "Could not detect Istio version, using default: $ISTIO_VERSION"
    log_warn "You can set ISTIO_VERSION environment variable to override"
}

validate_old_state() {
    log_info "Validating current state..."

    # Check for Istio CR
    if ! $CLI get istio "$OLD_REVISION" &> /dev/null; then
        log_error "Istio CR '$OLD_REVISION' not found"
        log_error "This script expects a Sail-managed Istio CR"
        exit 1
    fi

    # Detect Istio version from Sail operator
    detect_istio_version

    # Check for Gateways with old revision
    local gateway_count
    gateway_count=$($CLI get gateways -A -o json | jq -r ".items[] | select(.metadata.labels.\"istio.io/rev\" == \"$OLD_REVISION\") | .metadata.namespace + \"/\" + .metadata.name" | wc -l)

    if [ "$gateway_count" -eq 0 ]; then
        log_warn "No Gateways found with istio.io/rev=$OLD_REVISION label"
        log_warn "The migration will not have any Gateways to migrate"
        prompt_continue
    else
        log_info "Found $gateway_count Gateway(s) to migrate from $OLD_REVISION to $NEW_REVISION"
    fi

    # List the Gateways
    echo ""
    echo "=== Gateways to Migrate ==="
    $CLI get gateways -A -o json | jq -r ".items[] | select(.metadata.labels.\"istio.io/rev\" == \"$OLD_REVISION\") | \"  - \(.metadata.namespace)/\(.metadata.name)\""
    echo ""
}

clone_sail_operator_charts() {
    log_info "Fetching Istio charts from Sail operator repository..."

    # Clean up old cache if it exists
    if [ -d "$CHARTS_CACHE_DIR" ]; then
        log_debug "Removing old charts cache: $CHARTS_CACHE_DIR"
        rm -rf "$CHARTS_CACHE_DIR"
    fi

    # Clone just the specific chart directory we need using sparse checkout
    log_info "Cloning Sail operator charts (version: v$ISTIO_VERSION)..."

    mkdir -p "$CHARTS_CACHE_DIR"
    cd "$CHARTS_CACHE_DIR"

    git clone --depth 1 --filter=blob:none --sparse "$SAIL_OPERATOR_REPO" .
    git sparse-checkout set "resources/v${ISTIO_VERSION}/charts/istiod"

    # Verify the chart exists
    local chart_dir="$CHARTS_CACHE_DIR/resources/v${ISTIO_VERSION}/charts/istiod"
    if [ ! -d "$chart_dir" ]; then
        log_error "Istio chart not found at: $chart_dir"
        log_error "Available versions in Sail operator:"
        ls -1 "$CHARTS_CACHE_DIR/resources" 2>/dev/null || echo "  (failed to list)"
        exit 1
    fi

    log_info "Charts fetched successfully: $chart_dir"
    cd - > /dev/null
}

deploy_new_control_plane() {
    log_info "Deploying new Istio control plane with revision: $NEW_REVISION"
    log_info "Using Istio version: $ISTIO_VERSION (matching Sail operator)"

    # Clone Sail operator charts
    clone_sail_operator_charts

    # Install only istiod with revision using Sail operator's bundled chart
    local chart_path="$CHARTS_CACHE_DIR/resources/v${ISTIO_VERSION}/charts/istiod"

    log_info "Installing istiod chart from Sail operator (version: $ISTIO_VERSION)..."
    log_info "Chart path: $chart_path"

    # Set discovery address explicitly to ensure it's injected into Gateway deployments
    # This works around a known Istio issue where meshConfig.defaultConfig.discoveryAddress
    # doesn't always get propagated to Gateway deployments
    local discovery_address="istiod-${NEW_REVISION}.${NEW_CP_NAMESPACE}.svc:15012"
    log_info "Discovery address: $discovery_address"

    helm upgrade --install istiod-${NEW_REVISION} "$chart_path" \
        --namespace "$NEW_CP_NAMESPACE" \
        --set revision="$NEW_REVISION" \
        --set meshConfig.defaultConfig.discoveryAddress="$discovery_address" \
        --values "$HELM_VALUES_FILE" \

    log_info "Waiting for new control plane to be ready..."
    $CLI wait --for=condition=available --timeout=180s deployment/istiod-${NEW_REVISION} -n "$NEW_CP_NAMESPACE" || {
        log_error "New control plane did not become ready in time"
        log_error "Check logs with: $CLI logs -n $NEW_CP_NAMESPACE -l app=istiod,istio.io/rev=$NEW_REVISION"
        exit 1
    }

    log_info "New control plane deployed successfully"

    # Show the deployment
    echo ""
    echo "=== New Control Plane Status ==="
    $CLI get pods -n "$NEW_CP_NAMESPACE" -l istio.io/rev="$NEW_REVISION"
    echo ""
}

get_gateways_to_migrate() {
    # Returns list of "namespace/name" for Gateways with old revision
    $CLI get gateways -A -o json | jq -r ".items[] | select(.metadata.labels.\"istio.io/rev\" == \"$OLD_REVISION\") | \"\(.metadata.namespace)/\(.metadata.name)\""
}

validate_gateway() {
    local namespace="$1"
    local name="$2"
    local expected_rev="$3"

    log_debug "Validating Gateway $namespace/$name"

    # Check that Gateway has correct revision label
    local actual_rev
    actual_rev=$($CLI get gateway "$name" -n "$namespace" -o jsonpath='{.metadata.labels.istio\.io/rev}' 2>/dev/null || echo "")

    if [ "$actual_rev" != "$expected_rev" ]; then
        log_error "Gateway $namespace/$name has revision '$actual_rev', expected '$expected_rev'"
        return 1
    fi

    # Wait for Gateway to be Programmed
    log_debug "Waiting for Gateway $namespace/$name to be Programmed..."
    local elapsed=0
    while [ $elapsed -lt $VALIDATE_GATEWAY_TIMEOUT ]; do
        local programmed
        programmed=$($CLI get gateway "$name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || echo "Unknown")

        if [ "$programmed" = "True" ]; then
            log_debug "Gateway $namespace/$name is Programmed"
            return 0
        fi

        if [ "$programmed" = "False" ]; then
            local reason
            reason=$($CLI get gateway "$name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].reason}' 2>/dev/null || echo "Unknown")
            local message
            message=$($CLI get gateway "$name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].message}' 2>/dev/null || echo "Unknown")

            log_error "Gateway $namespace/$name Programmed=False (reason: $reason, message: $message)"
            return 1
        fi

        sleep 5
        elapsed=$((elapsed + 5))
    done

    log_error "Gateway $namespace/$name did not become Programmed within ${VALIDATE_GATEWAY_TIMEOUT}s"
    return 1
}

migrate_gateway() {
    local namespace="$1"
    local name="$2"

    log_info "Migrating Gateway: $namespace/$name"

    # Check current revision
    local current_rev
    current_rev=$($CLI get gateway "$name" -n "$namespace" -o jsonpath='{.metadata.labels.istio\.io/rev}' 2>/dev/null || echo "")

    if [ "$current_rev" != "$OLD_REVISION" ]; then
        log_warn "Gateway $namespace/$name has revision '$current_rev', expected '$OLD_REVISION'"
        log_warn "Skipping this Gateway"
        return 0
    fi
    
    #prompt_continue
    # Relabel the Gateway
    log_info "  Relabeling to istio.io/rev=$NEW_REVISION..."
    $CLI label gateway "$name" -n "$namespace" "istio.io/rev=$NEW_REVISION" --overwrite

    # Rollout the Gateway proxy deployment so pods get re-injected with new control plane discovery address
    log_info "  Rolling out Gateway proxy deployment..."
    local deployment_name
    deployment_name=$($CLI get deployments -n "$namespace" -l "gateway.networking.k8s.io/gateway-name=$name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$deployment_name" ]; then
        log_warn "  No proxy deployment found for Gateway $namespace/$name"
        log_warn "  Waiting for new control plane to create it..."
        sleep 5

        # Try again after waiting
        deployment_name=$($CLI get deployments -n "$namespace" -l "gateway.networking.k8s.io/gateway-name=$name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    fi

 #   if [ -n "$deployment_name" ]; then
 #       log_info "  Restarting deployment: $deployment_name"
        #$CLI rollout restart deployment "$deployment_name" -n "$namespace"

        # Wait for rollout to complete
        #log_info "  Waiting for rollout to complete..."
        #$CLI rollout status deployment "$deployment_name" -n "$namespace" --timeout=120s || {
        #    log_warn "  Rollout did not complete in time, continuing..."
        #}
#    else
#        log_warn "  Could not find Gateway proxy deployment to rollout"
#    fi

    # Validate the Gateway
    log_info "  Validating Gateway..."
    if ! validate_gateway "$namespace" "$name" "$NEW_REVISION"; then
        log_error "Gateway $namespace/$name failed validation after migration"
        log_error "You may need to roll back by running:"
        log_error "  $CLI label gateway $name -n $namespace istio.io/rev=$OLD_REVISION --overwrite"
        log_error "  $CLI rollout restart deployment -n $namespace -l gateway.networking.k8s.io/gateway-name=$name"
        exit 1
    fi

    # Check proxy deployment
    log_info "  Verifying proxy deployment..."
    local deployment_count
    deployment_count=$($CLI get deployments -n "$namespace" -l "gateway.networking.k8s.io/gateway-name=$name" --no-headers 2>/dev/null | wc -l)

    if [ "$deployment_count" -eq 0 ]; then
        log_error "  No proxy deployment found for Gateway $namespace/$name after migration"
        exit 1
    else
        log_info "  Proxy deployment is running"
        # Verify pods are using new control plane
        local pod_count
        pod_count=$($CLI get pods -n "$namespace" -l "gateway.networking.k8s.io/gateway-name=$name" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        if [ "$pod_count" -eq 0 ]; then
            log_warn "  No running pods found yet for Gateway proxy"
        else
            log_info "  Gateway has $pod_count running proxy pod(s)"
        fi
    fi

    log_info "  Gateway $namespace/$name migrated successfully ✓"
}

migrate_all_gateways() {
    log_info "Starting Gateway migration..."

    local gateways
    gateways=$(get_gateways_to_migrate)

    if [ -z "$gateways" ]; then
        log_warn "No Gateways found to migrate"
        return 0
    fi

    local total_count
    total_count=$(echo "$gateways" | wc -l)
    local current=0

    echo ""
    echo "=== Migrating $total_count Gateway(s) ==="
    echo ""

    while IFS= read -r gateway; do
        current=$((current + 1))
        local namespace
        namespace=$(echo "$gateway" | cut -d'/' -f1)
        local name
        name=$(echo "$gateway" | cut -d'/' -f2)

        echo ""
        log_info "[$current/$total_count] Processing Gateway: $namespace/$name"

        migrate_gateway "$namespace" "$name"

        # Pause between Gateways (except for the last one)
        if [ $current -lt $total_count ] && [ $PAUSE_BETWEEN_GATEWAYS -gt 0 ]; then
            log_info "Waiting ${PAUSE_BETWEEN_GATEWAYS}s before next Gateway..."
            sleep $PAUSE_BETWEEN_GATEWAYS
        fi
    done <<< "$gateways"

    echo ""
    log_info "All Gateways migrated successfully ✓"
}

verify_migration() {
    log_info "Verifying migration..."

    # Check that no Gateways have the old revision
    local old_count
    old_count=$($CLI get gateways -A -o json | jq -r ".items[] | select(.metadata.labels.\"istio.io/rev\" == \"$OLD_REVISION\") | .metadata.namespace + \"/\" + .metadata.name" | wc -l)

    if [ "$old_count" -gt 0 ]; then
        log_error "Found $old_count Gateway(s) still with old revision $OLD_REVISION:"
        $CLI get gateways -A -o json | jq -r ".items[] | select(.metadata.labels.\"istio.io/rev\" == \"$OLD_REVISION\") | \"  - \(.metadata.namespace)/\(.metadata.name)\""
        exit 1
    fi

    # Check that all Gateways have the new revision (that previously had old revision)
    local new_count
    new_count=$($CLI get gateways -A -o json | jq -r ".items[] | select(.metadata.labels.\"istio.io/rev\" == \"$NEW_REVISION\") | .metadata.namespace + \"/\" + .metadata.name" | wc -l)

    log_info "All $new_count Gateway(s) now have revision: $NEW_REVISION ✓"

    echo ""
    echo "=== Current Gateway Status ==="
    $CLI get gateways -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.gatewayClassName,REV:.metadata.labels.istio\.io/rev,PROGRAMMED:.status.conditions[?(@.type=="Programmed")].status'
    echo ""
}

delete_old_istio_cr() {
    log_info "Deleting old Istio CR: $OLD_REVISION"

    echo ""
    log_warn "This will delete the Sail-managed Istio control plane"
    log_warn "The Gateways are now managed by the new helm-direct control plane"
    prompt_continue

    $CLI delete istio "$OLD_REVISION" --wait=false

    log_info "Istio CR '$OLD_REVISION' deletion initiated"
    log_info "The Sail operator will clean up the old control plane resources"

    # Wait a bit and show what's being deleted
    sleep 5

    echo ""
    log_info "Checking old control plane namespace..."
    local old_namespace
    old_namespace="${OLD_CP_NAMESPACE:-openshift-ingress}"

    if $CLI get namespace "$old_namespace" &> /dev/null; then
        log_info "Pods remaining in $old_namespace:"
        $CLI get pods -n "$old_namespace" 2>/dev/null || echo "  (namespace may be terminating)"
    fi
}

cleanup_charts_cache() {
    if [ -d "$CHARTS_CACHE_DIR" ]; then
        log_info "Cleaning up charts cache: $CHARTS_CACHE_DIR"
        rm -rf "$CHARTS_CACHE_DIR"
    fi
}

print_summary() {
    echo ""
    echo "=========================================="
    echo "  Migration Complete!"
    echo "=========================================="
    echo ""
    echo "Summary:"
    echo "  - Old control plane: $OLD_REVISION (deleted)"
    echo "  - New control plane: $NEW_REVISION (revision: $NEW_REVISION)"
    echo "  - Namespace: $NEW_CP_NAMESPACE"
    echo "  - Charts source: Sail operator repository (v$ISTIO_VERSION)"
    echo ""
    echo "All Gateways are now managed by the new helm-direct Istio control plane."
    echo ""
    echo "Next steps:"
    echo "  1. Verify traffic is flowing correctly through your Gateways"
    echo "  2. Monitor the new control plane:"
    echo "     $CLI logs -n $NEW_CP_NAMESPACE -l app=istiod,istio.io/rev=$NEW_REVISION -f"
    echo ""
    echo "  3. (Optional) Uninstall Sail operator if no longer needed:"
    echo "     helm uninstall sail-operator -n openshift-operators"
    echo ""
    echo "Rollback (if needed):"
    echo "  To rollback, you would need to:"
    echo "  1. Reinstall the Sail-managed Istio CR"
    echo "  2. Relabel Gateways back to istio.io/rev=$OLD_REVISION"
    echo "  3. Delete the helm-direct control plane"
    echo ""

    # Cleanup
    cleanup_charts_cache
}

main() {
    echo "=========================================="
    echo "  Parallel Canary Migration"
    echo "=========================================="
    echo ""
    echo "Configuration:"
    echo "  Old revision: $OLD_REVISION"
    echo "  New revision: $NEW_REVISION"
    echo "  New control plane namespace: $NEW_CP_NAMESPACE"
    echo "  Helm values: $HELM_VALUES_FILE"
    if [ -n "$ISTIO_VERSION" ]; then
        echo "  Istio version (explicit): $ISTIO_VERSION"
    else
        echo "  Istio version: (will auto-detect from Sail operator)"
    fi
    echo ""

    check_prereqs
    validate_old_state

    echo ""
    echo "Configuration after detection:"
    echo "  Istio version: $ISTIO_VERSION"
    echo ""

    log_info "Starting migration process..."
    prompt_continue

    deploy_new_control_plane
    migrate_all_gateways
    verify_migration
    delete_old_istio_cr

    print_summary
}

main "$@"
