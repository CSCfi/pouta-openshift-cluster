#!/usr/bin/env bats

skip_if_sc_is_inactive() {
  if [[ ",$ACTIVE_STORAGE_CLASSES," != *,$1,* ]]; then
    skip "Storage class $1 is not active"
  fi
}
