# shellcheck shell=bash
# shellcheck disable=SC2034 # pf, pf_rel and pf_ci are the results the sourcing hook reads
#
# The path form of require-rule-read.sh and record-rule-read.sh (ww3d/playbook#537): one spelling for both sides of
# the project-root comparison. Bash builtins only.
#
#   path_form <path>          sets pf: backslashes as slashes, a drive letter D:/x as /D/x (the Git Bash form, so
#                             either spelling meets the other), no trailing slash
#   path_under <root> <path>  0 when path lies below root, and sets pf_rel to the part below it and pf_ci to 1
#                             where either side carries a drive letter (Windows): the comparison ignores case
#
# Git Bash mounts more than the drives: /tmp, /usr, /home stand for folders under the Windows user or the Git
# folder, which only `cygpath` (a process start per call) could map. A pair of such a path and a Windows path never
# matches: the Write/Edit gate lets the call pass, the read record counts nothing (the receipt line stays the second
# way). A test holds that.
path_form() { # path -> global pf
  local p="${1//\\//}"
  case "$p" in [A-Za-z]:/*) p="/${p:0:1}${p:2}" ;; esac
  pf="${p%/}"
}
path_under() { # root, path -> global pf_rel; status 1 when path is not below root
  local r p rc=1 nc=0
  case "$1$2" in *[A-Za-z]:[\\/]*) nc=1 ;; esac
  path_form "$1"; r="$pf"; path_form "$2"; p="$pf"
  pf_rel="" pf_ci="$nc"
  [ "$nc" = 0 ] || shopt -s nocasematch
  if [[ $p == "$r"/* ]]; then pf_rel="${p:${#r}+1}"; rc=0; fi
  [ "$nc" = 0 ] || shopt -u nocasematch
  return "$rc"
}
