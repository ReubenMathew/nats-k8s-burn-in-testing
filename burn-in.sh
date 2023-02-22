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
trap cleanup EXIT

function continousUpgrade() {
  #echo -e \
    #"==============================================\n" \
    #"\bInitializing Fault Injection (Rollout Restart)\n" \
    #"\b=============================================="
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

echo "NATS topology has been configured"

# Go client doing a load test 
cd bench/ 
continousUpgrade &
echo -e \
  "==================================================\n" \
  "\bRunning Load Test: JetStream Pull Durable Consumer\n" \
  "\b=================================================="
go run bench-pull-durable-consumer.go
echo -e \
  "\n====================================================\n" \
  "\bCompleted Load Test: JetStream Pull Durable Consumer\n" \
  "\b===================================================="

