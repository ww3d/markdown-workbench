#!/usr/bin/env bash

# The gate as CI runs it (.github/workflows/test.yml): restore, check, coverage and package, with --ci. No
# integration run: it needs a display and CI does not run it. The counterpart of CIBuild.cmd.

source="${BASH_SOURCE[0]}"
while [[ -h "$source" ]]; do
  scriptroot="$( cd -P "$( dirname "$source" )" && pwd )"
  source="$(readlink "$source")"
  [[ $source != /* ]] && source="$scriptroot/$source"
done
scriptroot="$( cd -P "$( dirname "$source" )" && pwd )"

exec "$scriptroot/build.sh" --restore --check --coverage --pack --ci "$@"
