#!/usr/bin/env bats

setup() {
    # Delete existing job if it is there so that a new job is always created
    oc -n $PROJECT_NAME delete job/egress-ip-checker || true

    # Build docker image if not present
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

teardown() {
    # Delete existing job if it is there so that a new job is always created
    oc -n $PROJECT_NAME delete job/egress-ip-checker || true
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
