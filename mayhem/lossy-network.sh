# Introduce random packet loss at each cluster server

CLUSTER_SIZE=5
TRAFFIC_SHAPING_CONTAINER="netshoot"
POD_PREFIX="nats-"
function run()
{
    local min_loss="3"
    local max_loss="10"

    for i in $(seq 0 $(( ${CLUSTER_SIZE} - 1 )));
    do
        local pod="${POD_PREFIX}${i}"
        local loss="$(( (${RANDOM} % (${max_loss} - ${min_loss})) + ${min_loss} ))"
        echo "🐵 Introducing ${loss}% packet loss on ${pod} network"
        kubectl exec "pod/${pod}" -c "${TRAFFIC_SHAPING_CONTAINER}" quiet -- tc qdisc add dev eth0 root netem loss "${loss}%"
    done

    # Wait forever for kill signal
    while true;
    do
        sleep 1
    done
}

function cleanup ()
{
    local cluster_size=5

    for i in $(seq 0 $(( ${CLUSTER_SIZE} - 1 )));
    do
        local pod="${POD_PREFIX}${i}"
        echo "🐵 Resetting traffic shaping for ${pod} network"
        kubectl exec "${pod}" -c "${TRAFFIC_SHAPING_CONTAINER}" -- tc qdisc delete dev eth0 root 2>/dev/null
    done
}