# Introduce random network latency at each cluster server

CLUSTER_SIZE=5
TRAFFIC_SHAPING_CONTAINER="netshoot"
POD_PREFIX="nats-"

function run()
{
    local min_delay="3"
    local max_delay="10"
    local cluster_size=5

    for i in $(seq 0 $(( ${CLUSTER_SIZE} - 1 )));
    do
        local pod="${POD_PREFIX}${i}"
        local random_delay="$(( (${RANDOM} % (${max_delay} - ${min_delay})) + ${min_delay} ))"
        local jitter="$(( ${RANDOM} %(${max_delay} - ${min_delay})))"
        echo "🐵 Introducing ${random_delay}ms delay on ${pod} network"
        kubectl exec "pod/${pod}" -c "${TRAFFIC_SHAPING_CONTAINER}" quiet -- tc qdisc add dev eth0 root netem delay "${random_delay}ms" "${jitter}ms" distribution normal
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