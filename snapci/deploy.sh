#!/usr/bin/env bash

set -xeuo pipefail

export CI=true

source $(dirname $BASH_SOURCE)/utils.sh

deploy "-dev"
