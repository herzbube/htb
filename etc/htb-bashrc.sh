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
# |                 - For sub-shells: ~/.bashrc
# |
# |                 Note that this is not a regular script! It must be invoked
# |                 by sourcing it (dot syntax, or the source shell builtin).
# |
# | Arguments:      None
# | Exit codes:     None
# | Dependencies:   bash (export -f)
# =========================================================================

# /////////////////////////////////////////////////////////////////////////
# // Aliases
# /////////////////////////////////////////////////////////////////////////

alias df="df -h"
alias l="ls -la"
alias _fl="fink list --width=200"

# /////////////////////////////////////////////////////////////////////////
# // Variables
# /////////////////////////////////////////////////////////////////////////

:  # no-op, currently no variables

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

function psg()
{
  case $(uname) in
    Linux)
      ps -ef | grep -i "$@" ;;
    Darwin)
      ps -axj | grep -i "$@" ;;
  esac
}
export -f psg

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

function _la1()
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
export -f _la1

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

function _la2()
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
export -f _la2

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

function _lclr()
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
export -f _lclr
