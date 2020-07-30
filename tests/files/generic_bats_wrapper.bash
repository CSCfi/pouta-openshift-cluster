#!/usr/bin/env bash

set -eu

num_failed=0
for test_dir in "$@"; do
    echo "Running test in $test_dir"

    cd "$test_dir" || exit
    ./run.bats
    result=$?
    cd .. || exit

    if [ "$result" -ne 0 ]; then
      ((num_failed++));
    fi
done

exit "$num_failed"
