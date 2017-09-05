#!/usr/bin/env bats

@test "build scanning container" {
    oc new-build --to scanner -D - < Dockerfile

    status=0
    for ((i=0;i<60;i++)); do
        if  oc get build -l build=scanner | grep Complete; then
            status=1
            break
        fi
      sleep 2
    done

    [ "$status" -eq 1 ]
}

@test "scan cluster" {

    target_dir=$(mktemp -d)
    cat /etc/hosts | grep -v localhost | cut -d " " -f 1 | sort | uniq \
      | xargs -n 1 dig +short -x > $target_dir/targets

    run oc create configmap scanner-config --from-file $target_dir/targets

    echo
    echo "scan targets:"
    cat $target_dir/targets
    echo

    rm -rf $target_dir

    scanjob=$(mktemp)
    sed -e "s|__PROJECT_NAME__|$project_name|g" scanjob_template.yml > $scanjob
    run oc create -f $scanjob
    rm $scanjob

    echo "waiting for scanner job to finish"
    for ((i=0;i<60;i++)); do
        oc get pod -l job-name=scanner | grep -q Completed && status=1 && break
        echo "  sleeping $i"
        sleep 2
    done

    [ "$status" -eq 1 ]

    run oc logs job/scanner
    echo
    echo "Raw nmap output"
    echo "-----------------------------------------------------------------------------"
    echo "$output"
    echo "-----------------------------------------------------------------------------"
    echo
    extra_lines=$(echo "$output" | grep " open " | egrep -v "^53/|^80/|^443/|^2049/|^8443/" | tee /dev/null)

    echo
    echo "Extra lines"
    echo "-----------------------------------------------------------------------------"
    echo "$extra_lines"
    echo "-----------------------------------------------------------------------------"
    echo

    [ "$extra_lines" == "" ]
}
