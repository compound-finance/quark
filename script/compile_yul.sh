#!/bin/bash

read -r -d '' yul <<- EOM
object "VmTest" {
  code {
    $1
  }
}
EOM

echo "$yul" | solc --yul --bin - | head -n 5 | tail -n 1
