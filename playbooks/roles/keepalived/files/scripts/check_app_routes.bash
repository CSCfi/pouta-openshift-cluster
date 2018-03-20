#!/bin/bash

set -e

# check that there is response from router on the localhost, 2 seconds timeout
curl -s -m 2 -o /dev/null http://localhost
