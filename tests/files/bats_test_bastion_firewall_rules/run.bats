#!/usr/bin/env bats

@test "test access to NRPE port in cluster" {
    temp_dir=$(mktemp -d)
    cat /etc/hosts | grep '^192' | awk '{print $1}' > $temp_dir/targets.txt

    run bash -c "nmap -Pn -i $temp_dir/targets.txt -p 5666 | grep -E 'filtered|closed'"
    rm -rf $temp_dir

    [ $status -ne 0 ]
}
