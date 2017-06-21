#!/usr/bin/env bash

# A simple script to build pac-deployer locally

set -ex

docker build --pull=true -t cscfi/pac-deployer .
