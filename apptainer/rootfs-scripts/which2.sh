# shellcheck shell=sh
# Initialization script for bash, sh, mksh and ksh
#
# agy-stack: patched copy of the base image's /etc/profile.d/which2.sh, bound
# over it at instance start (see shell_env_binds in scripts/common.sh).
#
# Why: the original ends with `export ${which_opt} which`, which exports the
# `which` shell function. Its body spans several lines, so the editor/agent
# language server - which snapshots a login shell's environment line by line -
# stores only the first line ("() {  ( alias;"). Every bash spawned from that
# snapshot then fails to import it and prints:
#     bash: which: line 1: syntax error: unexpected end of file
#     bash: error importing function definition for `which'
# Such a truncated BASH_FUNC_which%% variable cannot be removed from inside
# bash (the name is not a valid identifier), so the export is dropped here.
# The function itself is kept: `which` still resolves aliases and functions.

if [ -r /proc/$$/exe ]; then
    SHELLNAME=$(basename $(readlink /proc/$$/exe))
else
    SHELLNAME="unknown"
fi

case "$SHELLNAME" in
*ksh*)
    which_declare=""
    which_opt=""
    ;;
zsh)
    which_declare="typeset -f"
    which_opt=""
    ;;
bash|sh)
    which_declare="declare -f"
    which_opt="-f"
    ;;
*)
    which_declare=""
    which_opt=""
    ;;
esac

function which {
    (alias; eval ${which_declare}) | /usr/bin/which --tty-only --read-alias --read-functions --show-tilde --show-dot $@
}

export which_declare
# export ${which_opt} which   <-- disabled, see header
