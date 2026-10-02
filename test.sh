#!/usr/bin/env bash

source="${BASH_SOURCE[0]}"
while [[ -h "$source" ]]; do
  scriptroot="$( cd -P "$( dirname "$source" )" && pwd )"
  source="$(readlink "$source")"
  [[ $source != /* ]] && source="$scriptroot/$source"
done
scriptroot="$( cd -P "$( dirname "$source" )" && pwd )"

exec "$scriptroot/eng/common/build.sh" --test "$@"
