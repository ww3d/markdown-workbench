#!/usr/bin/env bash

# Entry point of the root scripts (build.sh, restore.sh, test.sh, eng/common/cibuild.sh): fetches the
# pinned Node and pnpm repo-local (tools.sh), then hands every option to the build flow, eng/build.ts,
# which is where tasks, switches and their documentation live (--help). Modeled on ww3d/atlas
# eng/common/build.sh; the same options as build.ps1, with one or two hyphens.
#
# Atlas-style action switches and --task are the same thing: --restore, --build, --test, --pack,
# --check, --coverage and --integrationTest each name a task; with none given, the task is All.

set -u
set -e

source="${BASH_SOURCE[0]}"
while [[ -h "$source" ]]; do
  scriptroot="$( cd -P "$( dirname "$source" )" && pwd )"
  source="$(readlink "$source")"
  [[ $source != /* ]] && source="$scriptroot/$source"
done
scriptroot="$( cd -P "$( dirname "$source" )" && pwd )"

# shellcheck source=tools.sh
. "$scriptroot/tools.sh"

build_args=()
while [[ $# -gt 0 ]]; do
  opt="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$opt" in
    -task | --task) build_args+=(--task "$2"); shift ;;
    -restore | --restore | -r) build_args+=(--task Restore) ;;
    -check | --check) build_args+=(--task Check) ;;
    -build | --build | -b) build_args+=(--task Build) ;;
    -test | --test | -t) build_args+=(--task Test) ;;
    -coverage | --coverage) build_args+=(--task Coverage) ;;
    -pack | --pack) build_args+=(--task Package) ;;
    -integrationtest | --integrationtest) build_args+=(--task Integration) ;;
    -norestore | --norestore | --no-restore) build_args+=(--no-restore) ;;
    -ci | --ci) build_args+=(--ci) ;;
    -artifactsdir | --artifactsdir | --artifacts-dir) build_args+=(--artifacts-dir "$2"); shift ;;
    -help | --help | -h) build_args+=(--help) ;;
    *) echo "build.sh: unknown option '$1' (see --help)" >&2; exit 1 ;;
  esac
  shift
done

cd "$repo_root"
initialize_toolchain
exec node eng/build.ts "${build_args[@]+"${build_args[@]}"}"
