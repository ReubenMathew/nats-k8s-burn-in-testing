# This file contains helper functions and it is sourced by the main script.

function mayhem()
{
    local mayhem_name="$1"
    local delay="$2"
    local mayhem_file="${MAYHEM_DIR}/${mayhem_name}.sh"

    test -f "${mayhem_file}" || fail "Not found: ${mayhem_file}"


    _mayhem "${mayhem_file}" "${delay}" >> "${MAYHEM_LOG_FILE}" 2>&1 &
    local child_pid="$!"

    echo "😵‍💫  Launched mayhem agent: ${mayhem_name}, starts in ${delay} seconds (pid: ${child_pid})"

    local pid_file="${MAYHEM_PIDS_DIR}/mayhem_${child_pid}.pid"
    echo "${child_pid}" > "${pid_file}"
}

# This executed as a forked process
function _mayhem() {
    local mayhem_file="$1"
    local delay="$2"

    # Source mayhem file as background process and write its pid to file
    # shellcheck disable=SC1090
    source "${mayhem_file}" || "Failed to source mayhem file: ${mayhem_file}"

    # Wait for the given delay
    sleep "${delay}"

    # If cleanup function is defined for the given mayhem
    if [ "$(type -t cleanup)" = "function" ]; then
        # Register cleanup function to be called on exit
        trap cleanup EXIT
    fi

    # Run the mayhem agent
    run

    exit 0
}

function stop_mayhem()
{
    # For each pid file, stop the corresponding mayhem process
    for pid_file in $(find ${MAYHEM_PIDS_DIR} -name '*.pid' -print0 | xargs -0); do
        local pid=$(cat "${pid_file}")
        if  kill -0 "${pid}" >/dev/null 2>&1; then
            echo "🛑  Stopping mayhem with pid: ${pid}"
            kill "${pid}"
        fi
        rm "${pid_file}"
    done
}
