#!/usr/bin/env bash
DIR=$(cd "$(dirname "$0")" && pwd)
bash "$DIR/launch.sh"
printf '\nServer stopped. Press Enter to close this window.\n'
read -r _
