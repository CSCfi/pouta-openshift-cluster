#!/usr/bin/env bash

num_failed=0
for test_dir in $*; do
    export project_name="system-tests-$(date '+%Y%m%d%H%M%S')-$(openssl rand -hex 6)"
    echo "Running test in $test_dir, Using project $project_name"
    oc new-project $project_name 2>&1 > /dev/null

    cd $test_dir
    ./run.bats
    result=$?
    cd ..

    oc project default 2>&1
    oc delete project $project_name

    if [ "$result" -ne 0 ]; then
      ((num_failed++));
    fi
done

exit $num_failed
