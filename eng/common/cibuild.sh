#!/usr/bin/env bash

# The full gate as CI runs it: a restore, then every task (All), with --ci. The counterpart of CIBuild.cmd.

source="${BASH_SOURCE[0]}"
while [[ -h "$source" ]]; do
  scriptroot="$( cd -P "$( dirname "$source" )" && pwd )"
  source="$(readlink "$source")"
  [[ $source != /* ]] && source="$scriptroot/$source"
done
scriptroot="$( cd -P "$( dirname "$source" )" && pwd )"

exec "$scriptroot/build.sh" --restore --task All --ci "$@"
