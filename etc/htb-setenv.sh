#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-setvar.sh
# | Date:           01 Jan 2011
# | Description:    Set up the HTB environment.
# |
# |                 Note that this is not a regular script! It must be invoked
# |                 by sourcing it (dot syntax, or the source shell builtin).
# |
# | Arguments:      None
# | Exit codes:     None
# | Dependencies:   None
# =========================================================================

if test -n "$HTB_ENVIRONMENT_INCLUDED"; then
  :  # no-op (can't use exit because we are sourced in)
else
  # Set the include guard
  export HTB_ENVIRONMENT_INCLUDED=1

  # Automatically export all variables that are set or changed. This lasts until
  # the "set +a" is encountered. Variables that are not intended for exporting
  # must be explicitly unset after use.
  set -a

  # Directory references

  # mktemp is not universally available, and it wants to create the directory
  # immediately -> stick to the traditional naming scheme
  HTB_TMP_DIR="/tmp/$HTB_SCRIPT_NAME.$$"
  HTB_CRON_DIR="$HTB_BASE_DIR/cron"
  HTB_ETC_DIR="$HTB_BASE_DIR/etc"
  HTB_BIN_DIR="$HTB_BASE_DIR/bin"
  HTB_SBIN_DIR="$HTB_BASE_DIR/sbin"
  HTB_INCLUDE_DIR="$HTB_BASE_DIR/include"
  HTB_LIB_DIR="$HTB_BASE_DIR/lib"
  HTB_MAN_DIR="$HTB_BASE_DIR/man"
  HTB_SRC_DIR="$HTB_BASE_DIR/src"
  HTB_LOG_DIR=/var/log

  # File references
  :  # no-op, currently no file references

  # Add to PATH
  if test -z "$(echo $PATH | fgrep "$HTB_BIN_DIR")"; then
    PATH="$HTB_BIN_DIR:$PATH"
  fi
  if test $(id -u) -eq 0; then
    if test -z "$(echo $PATH | fgrep "$HTB_SBIN_DIR")"; then
      PATH="$HTB_SBIN_DIR:$PATH"
    fi
  fi

  # The PAGER variable is used by man and other utilities for paginating
  # output to the screen
  if test -z "$PAGER"; then
    for HTB_PAGER in less more; do
      type $HTB_PAGER >/dev/null 2>&1
      if test $? -eq 0; then
        PAGER=$HTB_PAGER
        break
      fi
    done
    unset HTB_PAGER
  fi

  # The EDITOR variable is used by various utilities to invoke an interactive
  # editor program
  if test -z "$EDITOR"; then
    for HTB_EDITOR in vim vi nano; do
      type $HTB_EDITOR >/dev/null 2>&1
      if test $? -eq 0; then
        EDITOR=$HTB_EDITOR
        break
      fi
    done
    unset HTB_EDITOR
  fi

  # Set a few sane vi options in case .exrc is not present. Note that EXINIT
  # overrides .exrc, i.e. if EXINIT is set .exrc will not be read even if it
  # exists.
  if test ! -f "$HOME/.exrc"; then
    EXINIT="set noai redraw showmode"
  fi

  # Locale settings (cf. "man M locale"). For instance, LANG is used by vi for
  # properly displaying 8-bit characters.
  if test -z "$LANG"; then
    for HTB_LOCALE in de_CH.UTF-8 en_US.UTF-8 en_GB.UTF-8 de_CH.ISO8859-1 en_US.ISO8859-1 en_GB.ISO8859-1 de_CH en_US en_GB; do
      if test -n "$(locale -a | grep "^$HTB_LOCALE$")"; then
        LANG="$HTB_LOCALE"
        break
      fi
    done
    unset HTB_LOCALE
  fi

  # Determine the user's terminal device; unset the variable if no terminal
  # is connected (e.g. in a cron environment)
  HTB_TTY="$(tty)"
  if test "$HTB_TTY" = "not a tty"; then
    unset HTB_TTY
  fi

  # less can be configured to open .gz files and the like via the utility
  # lesspipe. If invoked without any parameters, lesspipe prints out a few
  # environment variables so that less will correctly use lesspipe.
  if test -z "$LESSOPEN"; then
    type lesspipe >/dev/null 2>&1
    if test $? -eq 0; then
      eval $(lesspipe)
    fi
  fi

  # Turn off automatic export of environment variables
  set +a
fi  # if test -z "$HTB_ENVIRONMENT_INCLUDED"; then
