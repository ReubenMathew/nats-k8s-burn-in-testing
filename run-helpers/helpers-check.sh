# This file contains helper functions and it is sourced by the main script.

function check_files_and_dirs()
{
    local main_script="./run-test.sh"
    test -f "${main_script}" || fail "Must run from the project root directory"

    local files=(
        "./menu.sh"
        "${K3D_CLUSTER_CONFIG}"
        "${DOCKERFILE}"
        "${HELM_CHART_VALUES}"
    )
    for file in "${files[@]}"; do
        test -f "${file}" || fail "Not found: ${file}"
    done

    local dirs=(
        "${HELM_CHART_CONFIG}"
        "${TESTS_DIR}"
        "${MAYHEM_DIR}"
        "${TESTS_DIR}"
    )
    for dir in "${dirs[@]}"; do
        test -d "${dir}" || fail "Not found: ${dir}"
    done

    mkdir -p "${MAYHEM_PIDS_DIR}" || fail "Failed to create directory: ${MAYHEM_PIDS_DIR}"
}

function check_bin_dependencies()
{
    for bin in "${BIN_DEPENDENCIES[@]}"; do
        command -v "${bin}" >/dev/null 2>&1 || fail "Missing dependency: ${bin}"
    done
}

function check_docker_running()
{
    k3d node list >/dev/null 2>&1 || fail "Docker not running? (failed to list nodes)"
}
