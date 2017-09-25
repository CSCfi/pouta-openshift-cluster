#!/usr/bin/env bash

num_failed=0
for test_dir in $*; do
    echo "Running test in $test_dir"

    cd $test_dir
    ./run.bats
    result=$?
    cd ..

    if [ "$result" -ne 0 ]; then
      ((num_failed++));
    fi
done

exit $num_failed
