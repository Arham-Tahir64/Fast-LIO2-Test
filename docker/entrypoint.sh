#!/usr/bin/env bash
set -eo pipefail

source /opt/ros/jazzy/setup.bash
source /opt/livox_ws/install/setup.bash
source /opt/fastlio_ws/install/local_setup.bash

exec "$@"
