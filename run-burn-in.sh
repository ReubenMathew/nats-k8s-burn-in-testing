#!/bin/bash -e

function cleanup()
{
  # Kill any background jobs
  kill $(jobs -p) &>/dev/null
  # Uninstall Helm release
  helm uninstall nats
  # Delete K3 cluster
  k3d cluster delete k3-cluster
}
#trap cleanup EXIT

function continousUpgrade() {
  while true; do
    echo -e "\nFAULT INJECTION: rollout restart of statefulset/nats"
    # using rollout status to block until restart has completed
    kubectl rollout restart statefulset/nats 1>/dev/null
    kubectl rollout status statefulset/nats --timeout=2m 1>/dev/null
    sleep 5
  done
}

cd "$(dirname $0)"

# Create a single node K3 cluster
k3d cluster create --config ./k3d/k3-cluster.yaml

# Build and install Helm dependencies
helm repo add nats https://nats-io.github.io/k8s/helm/charts/
helm dependency build ./nats

# Helm deploy
helm upgrade \
    --debug \
    --install \
    --wait \
    --reset-values \
    nats \
    ./nats

echo "Success: NATS Topology has been configured"

# Go client doing a load test 
#continousUpgrade &
#echo -e \
  #"==================\n" \
  #"\bRunning Load Tests\n" \
  #"\b=================="
#cd bench && go run main.go
#echo -e \
  #"\n====================\n" \
  #"\bCompleted Load Tests\n" \
  #"\b===================="

