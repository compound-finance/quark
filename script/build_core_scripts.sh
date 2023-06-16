#!/bin/bash

set -eo pipefail

forge build --contracts ./core_scripts/ --skip ".yul" --optimize --optimizer-runs 200
