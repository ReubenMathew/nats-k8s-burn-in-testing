# This file contains helper functions and it is sourced by the main script.

function deploy_nats_cluster()
{
    local chart_name="nats"
    local timeout="120s"

    # Build and install Helm dependencies
    echo "⚙️ Building Helm chart"
    helm repo add nats "${UPSTREAM_HELM_CHART}" || fail "Failed to add Helm upstream repo"
    helm dependency build "${HELM_CHART_CONFIG}" || fail "Failed to build dependencies"

    # Install the chart
    echo "🚀 Installing Helm chart (timeout: ${timeout})"
    helm install "${chart_name}" "${HELM_CHART_CONFIG}" \
        --values "${HELM_CHART_VALUES}" \
        --wait \
        --timeout "${timeout}" || fail "Failed to install chart"

    # Wait for pods ready (superfluous, but just in case)
    kubectl wait --for condition=ready pods --all --timeout="${timeout}" || fail "Timeout waiting for pods"
}