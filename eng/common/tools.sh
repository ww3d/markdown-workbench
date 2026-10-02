#!/usr/bin/env bash

# Toolchain bootstrap (bash): the pinned Node and pnpm, repo-local. The counterpart of tools.ps1 - see
# there for the rules; the same behavior, in the same order.
#
# The pins are read, never repeated here: Node from package.json devEngines.runtime (an exact version),
# pnpm from package.json packageManager. A Node or pnpm already on the PATH is used only when its
# version equals the pin; any other is never used - the pinned one is fetched into .tools/ instead, and
# only this process's PATH learns about it. Needs only bash, curl or wget, tar, and sha256sum/shasum.
#   MARKDOWN_WORKBENCH_NODE_DIST_URL  replaces https://nodejs.org/dist (a mirror, or the tests' server)

# Source of this file: eng/common/tools.sh -> the repo root is two levels up.
tools_source="${BASH_SOURCE[0]}"
while [[ -h "$tools_source" ]]; do
  tools_dir="$( cd -P "$( dirname "$tools_source" )" && pwd )"
  tools_source="$(readlink "$tools_source")"
  [[ $tools_source != /* ]] && tools_source="$tools_dir/$tools_source"
done
repo_root="$( cd -P "$( dirname "$tools_source" )/../.." && pwd )"
tools_dir="$repo_root/.tools"

tools_fail() {
  echo "tools.sh: $*" >&2
  return 1
}

# The "version" of package.json's devEngines.runtime object, which must name node.
get_node_pin() {
  local block pin
  block="$(tr -d '\r\n' < "$repo_root/package.json" | grep -o '"devEngines"[^]]*"runtime"[[:space:]]*:[[:space:]]*{[^}]*}')" || true
  pin="$(printf '%s' "$block" | grep -o '"version"[[:space:]]*:[[:space:]]*"[0-9]*\.[0-9]*\.[0-9]*"' | grep -o '[0-9]*\.[0-9]*\.[0-9]*')" || true
  if [[ -z "$pin" ]] || ! printf '%s' "$block" | grep -q '"name"[[:space:]]*:[[:space:]]*"node"'; then
    tools_fail "package.json devEngines.runtime must name node with an exact version (e.g. '26.10.0') - the pin the build fetches."
    return 1
  fi
  printf '%s\n' "$pin"
}

# The version of package.json's packageManager ('pnpm@12.6.0', an optional +hash suffix dropped).
get_pnpm_pin() {
  local pin
  pin="$(tr -d '\r\n' < "$repo_root/package.json" | grep -o '"packageManager"[[:space:]]*:[[:space:]]*"pnpm@[^"+]*' | sed 's/.*pnpm@//')" || true
  if [[ -z "$pin" ]]; then
    tools_fail "package.json packageManager is not 'pnpm@<version>' - the build cannot resolve pnpm."
    return 1
  fi
  printf '%s\n' "$pin"
}

# The version a command on the PATH reports, 'v' prefix dropped; empty when there is none.
get_tool_version() {
  command -v "$1" > /dev/null 2>&1 || return 0
  local out
  out="$("$1" --version 2> /dev/null)" || return 0
  printf '%s\n' "${out#v}"
}

# nodejs.org's platform name of this machine, e.g. 'linux-x64'; part of the .tools folder names, since one
# checkout may be built from Windows and from WSL alike.
get_platform() {
  local os arch
  case "$(uname -s)" in
    Linux) os=linux ;;
    Darwin) os=darwin ;;
    *) tools_fail "unsupported OS '$(uname -s)' - use Build.cmd on Windows."; return 1 ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) arch=x64 ;;
    arm64 | aarch64) arch=arm64 ;;
    *) tools_fail "unsupported architecture '$(uname -m)' - Node publishes x64 and arm64."; return 1 ;;
  esac
  printf '%s-%s\n' "$os" "$arch"
}

# nodejs.org's archive name for this machine: tar.gz (gzip is everywhere, xz is not).
get_node_archive() {
  local platform
  platform="$(get_platform)" || return 1
  printf 'node-v%s-%s.tar.gz\n' "$1" "$platform"
}

# Why the PATH did not do: 'the one on the PATH is X' or 'none on the PATH'.
why_not() {
  if [[ -n "$1" ]]; then echo "the one on the PATH is $1"; else echo "none on the PATH"; fi
}

download() {
  local url="$1" out="$2" attempt
  for attempt in 1 2 3; do
    if command -v curl > /dev/null 2>&1; then
      curl -fsSL --retry 0 -o "$out" "$url" && return 0
    elif command -v wget > /dev/null 2>&1; then
      wget -q -O "$out" "$url" && return 0
    else
      tools_fail "neither curl nor wget is installed."
      return 1
    fi
    echo "  GET $url failed - retrying ($attempt of 3)." >&2
    sleep $((attempt * 2))
  done
  tools_fail "unable to download $url in 3 attempts."
}

sha256_of() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

tools_work=""

# Removes the download folder of install_node and the traps that guard it; safe to call twice.
drop_download() {
  [[ -n "$tools_work" ]] && rm -rf "$tools_work"
  tools_work=""
  trap - EXIT INT TERM
}

# Downloads the pinned Node, checks the archive against the release's SHASUMS256.txt (a mismatch
# aborts, nothing is extracted) and unpacks it to $2. The download folder goes on every way out,
# an interrupt (Ctrl-C) included.
install_node() {
  local version="$1" dir="$2" dist archive expected actual
  dist="${MARKDOWN_WORKBENCH_NODE_DIST_URL:-https://nodejs.org/dist}"
  dist="${dist%/}"
  archive="$(get_node_archive "$version")" || return 1
  mkdir -p "$tools_dir/node" || { tools_fail "cannot create $tools_dir/node."; return 1; }
  tools_work="$(mktemp -d "$tools_dir/node/.download-XXXXXX")" || tools_work=""
  if [[ -z "$tools_work" ]]; then
    tools_fail "cannot create a download folder in $tools_dir/node (disk full or not writable?)."
    return 1
  fi
  trap drop_download EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  echo "  Fetching Node $version ($archive) from $dist."
  download "$dist/v$version/SHASUMS256.txt" "$tools_work/SHASUMS256.txt" || { drop_download; return 1; }
  expected="$(grep -E "^[0-9a-f]{64}[[:space:]]+\*?$archive[[:space:]]*\$" "$tools_work/SHASUMS256.txt" | head -n1 | cut -d' ' -f1)"
  if [[ -z "$expected" ]]; then
    drop_download
    tools_fail "SHASUMS256.txt of Node $version does not list $archive."
    return 1
  fi
  download "$dist/v$version/$archive" "$tools_work/$archive" || { drop_download; return 1; }
  actual="$(sha256_of "$tools_work/$archive")"
  if [[ "$actual" != "$expected" ]]; then
    drop_download
    tools_fail "checksum mismatch for $archive: SHASUMS256.txt says $expected, the download is $actual. Nothing was installed."
    return 1
  fi
  mkdir -p "$tools_work/unpacked"
  tar -xzf "$tools_work/$archive" -C "$tools_work/unpacked" || { drop_download; return 1; }
  rm -rf "$dir"
  if ! mv "$tools_work/unpacked/"* "$dir"; then
    drop_download
    tools_fail "cannot move the unpacked Node to $dir."
    return 1
  fi
  drop_download
}

initialize_node() {
  local pin found dir name
  pin="$(get_node_pin)" || return 1
  found="$(get_tool_version node)"
  if [[ "$found" == "$pin" ]]; then
    echo "Node $pin: using the one on the PATH."
    return 0
  fi
  name="$pin-$(get_platform)" || return 1
  dir="$tools_dir/node/$name"
  if [[ ! -x "$dir/bin/node" ]]; then
    echo "Node $pin ($(why_not "$found")) - fetching it into .tools/node/$name (this repo only)..."
    install_node "$pin" "$dir" || return 1
  fi
  export PATH="$dir/bin:$PATH"
  found="$(get_tool_version node)"
  if [[ "$found" != "$pin" ]]; then
    tools_fail "Node $pin is still not what runs after the install (found: '$found')."
    return 1
  fi
  echo "Node $pin ready (.tools/node/$name)."
}

initialize_pnpm() {
  local pin found dir name
  pin="$(get_pnpm_pin)" || return 1
  found="$(get_tool_version pnpm)"
  if [[ "$found" == "$pin" ]]; then
    echo "pnpm $pin: using the one on the PATH."
    return 0
  fi
  # pnpm 12 is a native binary that npm picks per platform, so the platform is part of the folder name too.
  name="$pin-$(get_platform)" || return 1
  dir="$tools_dir/pnpm/$name"
  export PATH="$dir/node_modules/.bin:$PATH"
  if [[ "$(get_tool_version pnpm)" != "$pin" ]]; then
    echo "pnpm $pin ($(why_not "$found")) - fetching it with npm into .tools/pnpm/$name (this repo only)..."
    # npm ships with Node (Corepack no longer does since Node 25) and checks the registry's integrity hash.
    npm install --prefix "$dir" "pnpm@$pin" --no-audit --no-fund --loglevel=error || return 1
  fi
  found="$(get_tool_version pnpm)"
  if [[ "$found" != "$pin" ]]; then
    tools_fail "pnpm $pin is still not what runs after the install (found: '$found')."
    return 1
  fi
  echo "pnpm $pin ready (.tools/pnpm/$name)."
}

enable_system_ca() {
  # Node (and so npm and everything the build starts under it) also trusts the system's certificates, which a
  # company proxy with its own certificate is in (on Linux: the OpenSSL file and directory, SSL_CERT_FILE and
  # SSL_CERT_DIR included). Node 22.19 / 24.6 and later read the variable; an older one ignores it. A value the
  # caller set stays.
  export NODE_USE_SYSTEM_CA="${NODE_USE_SYSTEM_CA:-1}"
}

initialize_toolchain() {
  enable_system_ca
  initialize_node && initialize_pnpm
}
