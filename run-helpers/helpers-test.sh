# This file contains helper functions and it is sourced by the main script.

function build_test()
{
    echo "🛠️  Building test"

    # Temporarily change directory to the test directory
    pushd "${TESTS_DIR}" >/dev/null 2>&1 || fail "Failed to change directory to: ${TESTS_DIR}"

    go build -o "${TEST_BIN}" || fail "Failed to build test"

    # Return to the previous directory
    popd >/dev/null 2>&1 || fail "Failed to change directory from: ${TESTS_DIR}"
}

function run_test()
{
    local test_name="$1"
    local duration="$2"
    local test_exec="${TESTS_DIR}/${TEST_BIN}"

    test -x "${test_exec}" || fail "Not found: ${test_exec}"

    echo "🏃‍♀️  Running test: ${test_name} (duration: ${duration})"

    # Run the test
    "${test_exec}" --wipe --test "${test_name}" --duration "${duration}" || fail "Test failed: ${test_name}"
}