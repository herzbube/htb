#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-bashrc.sh
# | Date:           01 Jan 2011
# | Description:    Define a number of aliases, functions and variables that
# |                 are not inherited by a sub-shell and therefore need to be
# |                 set again for each sub-shell.
# |
# |                 Places to invoke this script are
# |                 - For the login shell: ~/.profile (this is required because
# |                   login shells do not execute ~/.bashrc)
# |                 - For sub-shells: ~/.bashrc or ~/.zshrc
# |
# |                 Note that this is not a regular script! It must be invoked
# |                 by sourcing it (dot syntax, or the source shell builtin).
# |
# | Arguments:      None
# | Exit codes:     None
# | Dependencies:   None
# =========================================================================

# /////////////////////////////////////////////////////////////////////////
# // Aliases
# /////////////////////////////////////////////////////////////////////////

alias df="df -h"
alias l="ls -la"
alias _fl="fink list --width=200"

case $(uname) in
  Linux)
    which dircolors >/dev/null
    if test $? -eq 0; then
      test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
      alias ls='ls --color=auto'
    fi
    ;;
  Darwin)
    alias ls='ls -G'
    ;;
esac

# /////////////////////////////////////////////////////////////////////////
# // Variables
# /////////////////////////////////////////////////////////////////////////

if test -n "$BASH"; then
  HTB_RUNS_IN_BASH=1
elif test -n "$ZSH_NAME"; then
  HTB_RUNS_IN_ZSH=1
fi

# Required on macOS so that the Homebrew-installed GnuPG is capable of
# obtaining a pass phrase from the user. Without this, a command line
# such as
#   echo "test" | gpg --clearsign
# will fail with this rather cryptic message:
#   Inappropriate ioctl for device
GPG_TTY=$(tty)
export GPG_TTY

# /////////////////////////////////////////////////////////////////////////
# // Functions
# /////////////////////////////////////////////////////////////////////////

# +------------------------------------------------------------------------
# | Lists processes that contain the specified search string. The Search is
# | performed by grep, the search string is treated case insensitive.
# +------------------------------------------------------------------------
# | Arguments:
# |  * Search string
# +------------------------------------------------------------------------
# | Return values:
# |  None
# +------------------------------------------------------------------------

psg()
{
  case $(uname) in
    Linux)
      ps -ef | grep -i "$@" ;;
    Darwin)
      ps -axj | grep -i "$@" ;;
  esac
}
if test -n "$HTB_RUNS_IN_BASH"; then
  export -f psg
fi

# +------------------------------------------------------------------------
# | Processes a LaTeX source file, converts the result to a .pdf and and opens
# | that .pdf. This function uses the commands "latex" and "dvipdf".
# +------------------------------------------------------------------------
# | Arguments:
# |  * File to process (without .tex)
# +------------------------------------------------------------------------
# | Return values:
# |  * 0: Success
# |  * 1: Error
# +------------------------------------------------------------------------

_la1()
{
  if test $# -eq 0; then
    echo Argument is missing
    return 1
  else
    latex "$1"
    if test $? -ne 0; then
      return 1
    fi
    latex "$1"
    if test $? -ne 0; then
      return 1
    fi
    dvipdf "$1"
    if test $? -ne 0; then
      return 1
    fi
    open "$1".pdf
  fi
}
if test -n "$HTB_RUNS_IN_BASH"; then
  export -f _la1
fi

# +------------------------------------------------------------------------
# | Processes a LaTeX source file, converts the result to a .pdf and and opens
# | that .pdf. This function uses the command "pdflatex".
# +------------------------------------------------------------------------
# | Arguments:
# |  * File to process (without .tex)
# +------------------------------------------------------------------------
# | Return values:
# |  * 0: Success
# |  * 1: Error
# +------------------------------------------------------------------------

_la2()
{
  if test $# -eq 0; then
    echo Argument is missing
    return 1
  else
    pdflatex "$1"
    if test $? -ne 0; then
      return 1
    fi
    pdflatex "$1"
    if test $? -ne 0; then
      return 1
    fi
    open "$1".pdf
  fi
}
if test -n "$HTB_RUNS_IN_BASH"; then
  export -f _la2
fi

# +------------------------------------------------------------------------
# | Remove temporary files created by LaTeX.
# +------------------------------------------------------------------------
# | Arguments:
# |  * File prefix
# +------------------------------------------------------------------------
# | Return values:
# |  * 0: Success
# |  * 1: Error
# +------------------------------------------------------------------------

_lclr()
{
  if test $# -eq 0; then
    echo Argument is missing
    return 1
  else
    rm -f $1.aux $1.dvi $1.log $1.out $1.pdf $1.toc $1.lof $1.lot $1.bbl $1.blg $1.glo
    if test $? -ne 0; then
      return 1
    fi
  fi
}
if test -n "$HTB_RUNS_IN_BASH"; then
  export -f _lclr
fi

# /////////////////////////////////////////////////////////////////////////
# // Other settings
# /////////////////////////////////////////////////////////////////////////

# Make sure to use the Emacs keymap in zsh to support the same key bindings
# as in bash (e.g. Ctrl+A / Ctrl+E go to line start/end, Ctrl+R searches the
# command history).
if test -n "$HTB_RUNS_IN_ZSH"; then
  bindkey -e
fi
