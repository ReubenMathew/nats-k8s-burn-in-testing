# Introduce random network latency at each cluster server

function run()
{
    local min_delay="3"
    local max_delay="10"

    for pod in "${POD_NAMES[@]}";
    do
        local random_delay=$(random_number_between ${min_delay} ${max_delay})
        local jitter=$(random_number_between 1 ${max_delay})
        echo "🐵 Introducing delay ${random_delay}ms ± ${jitter} on ${pod} network"
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
    for pod in "${POD_NAMES[@]}";
    do
        echo "🐵 Resetting traffic shaping for ${pod} network"
        kubectl exec "pod/${pod}" -c "${TRAFFIC_SHAPING_CONTAINER}" quiet -- tc qdisc delete dev eth0 root 2>/dev/null
    done
}
