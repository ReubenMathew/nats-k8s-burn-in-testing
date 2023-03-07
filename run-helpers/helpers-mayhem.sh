# This file contains helper functions and it is sourced by the main script.

function mayhem()
{
    local mayhem_name="$1"
    local mayhem_file="${MAYHEM_DIR}/${mayhem_name}.sh"
    local mayhem_log="${MAYHEM_DIR}/${mayhem_name}.log"

    test -f "${mayhem_file}" || fail "Not found: ${mayhem_file}"

    echo "🤯  Running mayhem: ${mayhem_name}"

    # Source mayhem file as background process and write its pid to file
    # shellcheck disable=SC1090
    source "${mayhem_file}" 2>&1 >> "${mayhem_log}"  &
    local pid=$!
    echo "$pid" > "${MAYHEM_PIDS_DIR}/${mayhem_name}_${pid}.pid"

    echo "😵‍💫  Started mayhem ${mayhem_name} (pid: ${pid}, logs to: ${mayhem_log})"
}

function stop_mayhem()
{
    # If any pid file exists
    if [ ! -n "$(ls -A "${MAYHEM_PIDS_DIR}")" ]; then
        return
    fi

    # For each pid file, stop the corresponding mayhem process
    for pid_file in "${MAYHEM_PIDS_DIR}"/*.pid; do
        local pid=$(cat "${pid_file}")
        if  kill -0 "${pid}" >/dev/null 2>&1; then
            echo "🔫  Stopping mayhem with pid: ${pid}"
            kill "${pid}"
        fi
        rm "${pid_file}"
    done
}