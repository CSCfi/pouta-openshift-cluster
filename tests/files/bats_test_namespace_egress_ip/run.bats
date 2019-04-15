#!/usr/bin/env bats

@test "build egress-ip-checker container" {
    if ! oc -n $PROJECT_NAME get bc egress-ip-checker; then
        oc -n $PROJECT_NAME new-build --to egress-ip-checker -D - < Dockerfile
    fi

    status=0
    for ((i=0;i<60;i++)); do
        if  oc -n $PROJECT_NAME get build -l build=egress-ip-checker | grep Complete; then
            status=1
            break
        fi
      sleep 2
    done

    [ "$status" -eq 1 ]
}

@test "check the namespace egress ip" {

    ipcheck=$(mktemp)
    echo $ipcheck
    sed -e "s|__PROJECT_NAME__|$PROJECT_NAME|g" check_egress_ip_job.yml > $ipcheck
    run oc -n $PROJECT_NAME create -f $ipcheck
    rm $ipcheck

    echo "waiting for egress ip job to finish"
    for ((i=0;i<60;i++)); do
        oc -n $PROJECT_NAME get pod -l job-name=egress-ip-checker | grep -q Completed && status=1 && break
        echo "  sleeping $i"
        sleep 2
    done

    [ "$status" -eq 1 ]

    current_ip=$(oc -n $PROJECT_NAME logs job/egress-ip-checker)

    [ "$current_ip" == "$PROJECT_IP" ]
}
