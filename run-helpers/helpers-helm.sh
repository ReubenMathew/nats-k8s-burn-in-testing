# This file contains helper functions and it is sourced by the main script.

function deploy_nats_cluster()
{
    local chart_name="nats"
    local timeout="120s"

    # Build and install Helm dependencies
    echo "⚙️  Building Helm chart"
    helm repo add nats "${UPSTREAM_HELM_CHART}" || fail "Failed to add Helm upstream repo"
    helm dependency build "${HELM_CHART_CONFIG}" || fail "Failed to build dependencies"

    if helm status "${chart_name}"; then
        echo "⚠️  Helm chart already installed"
        echo "🚀 Upgrading Helm chart (timeout: ${timeout})"
        helm upgrade "${chart_name}" "${HELM_CHART_CONFIG}" \
            --values "${HELM_CHART_VALUES}" \
            --install \
            --wait \
            --timeout "${timeout}" || fail "Failed to install chart"
    else
        # Install the chart
        echo "🚀 Installing Helm chart (timeout: ${timeout})"
        helm install "${chart_name}" "${HELM_CHART_CONFIG}" \
            --values "${HELM_CHART_VALUES}" \
            --wait \
            --timeout "${timeout}" || fail "Failed to install chart"
    fi

    # Wait for pods ready (superfluous, but just in case)
    kubectl wait --for condition=ready pods --all --timeout="${timeout}" >/dev/null || fail "Timeout waiting for pods"

    # Wait for a potential previous rollouts still running
    kubectl rollout status statefulset/nats --timeout="${timeout}" >/dev/null || fail "Timeout waiting for rollout"
}