#!/usr/bin/env bash

set -eu

num_failed=0
for test_dir in "$@"; do
    project_name="system-tests-$(date '+%Y%m%d%H%M%S')-$(openssl rand -hex 6)"
    export project_name
    echo "Running test in $test_dir, Using project $project_name"
    oc new-project "$project_name" > /dev/null 2>&1

    cd "$test_dir" || exit
    ./run.bats
    result=$?
    cd .. || exit

    oc project default 2>&1
    oc delete project "$project_name"

    if [ "$result" -ne 0 ]; then
      ((num_failed++));
    fi
done

exit "$num_failed"
