#!/usr/bin/env bash

# A simple script to build poc-deployer locally

set -ex

docker build --pull=true -t cscfi/poc-deployer .
