# color-grep initialization
#
# Patched copy of the host /etc/profile.d/colorgrep.sh, bound over the original
# at instance start (see shell_env_binds in scripts/common.sh).
#
# The host version calls /usr/libexec/grepconf.sh unguarded. That helper is not
# part of the SIF, and the host /etc/profile.d tree is visible inside the
# instance, so every login shell printed:
#   bash: /usr/libexec/grepconf.sh: No such file or directory
# colorzgrep.sh already carries this guard; colorgrep.sh does not.

[ -f /usr/libexec/grepconf.sh ] || return

/usr/libexec/grepconf.sh -c || return

alias grep='grep --color=auto' 2>/dev/null
alias egrep='egrep --color=auto' 2>/dev/null
alias fgrep='fgrep --color=auto' 2>/dev/null
