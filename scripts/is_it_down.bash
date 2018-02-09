#!/bin/bash
if [ -z $ADDR ]; then
    echo "Set ADDR before running the script"
    exit 1
fi

set -e

echo "Started polling $ADDR at: $(date)"

while true; do
    if ! curl -s -k -o /dev/null --connect-timeout 5 https://$ADDR; then
        echo "It's down! $(date)"
    else
        echo "It's up. $(date)"
    fi
    sleep 5
done
