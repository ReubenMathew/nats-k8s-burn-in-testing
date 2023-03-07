
# Restarts all pods (in order) using the 'rollout' command
function run()
{
    # Max time that a rollout can take
    local timeout="120s"
    # Time between rolling restarts
    local pause="5"

    while true;
    do
        echo "🐵 Begin rolling restart"
        kubectl rollout restart statefulset/nats 1>/dev/null || fail "Failed to initiate rolling restart"
        kubectl rollout status statefulset/nats --timeout="${timeout}" || fail "Failed to complete rolling restart"
        echo "🐵 Completed rolling restart"
        sleep "${pause}"
    done
}