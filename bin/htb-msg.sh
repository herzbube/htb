#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-msg.sh
# | Date:           01 Jan 2011
# | Description:    Print a message to stderr and optionally wait for the
# |                 user pressing <ENTER> in confirmation. Do not print
# |                 anything and do not wait if no tty is connected.
# |
# | Arguments:      -h: Print a short help page
# |                 -s: Stop and wait until the user has pressed <ENTER> to
# |                     confirm the message
# |                 -t <timeout>: Wait only for <timeout> seconds
# |                 messagetext: Message text to print
# |
# | Exit codes:     0: No error
# |                 2: Aborted by signal (e.g. Ctrl+C)
# |                 3: Error during initialisation
# |                 4: Error while processing arguments
# |                 5: Error during main program
# |                 6: Timeout exceeded
# |
# | Dependencies:   bash (implementation of stop feature uses "read -t")
# =========================================================================

# /////////////////////////////////////////////////////////////////////////
# // Functions
# /////////////////////////////////////////////////////////////////////////

# +------------------------------------------------------------------------
# | Exits the program using the given exit code.
# +------------------------------------------------------------------------
# | Arguments:
# |  * Exit code
# |  * Error message: This argument is optional. If specified, and if connected
# |    to a tty, the error message is printed to stderr.
# +------------------------------------------------------------------------
# | Return values:
# |  None
# +------------------------------------------------------------------------
# | Global variables used:
# |  * HTB_TTY
# |  * HTB_SCRIPT_NAME
# +------------------------------------------------------------------------
# | Global functions called:
# |  None
# +------------------------------------------------------------------------
# | HTB script invoked:
# |  None
# +------------------------------------------------------------------------

HTB_CLEANUP_AND_EXIT()
{
  typeset EXIT_STATUS=$1
  typeset ERROR_MESSAGE="$2"

  # Print message to screen only if a tty is connected
  if test -n "$ERROR_MESSAGE"; then
    if test -n "$HTB_TTY"; then
      echo "$HTB_SCRIPT_NAME: $ERROR_MESSAGE" >&2
    fi
  fi

  exit $EXIT_STATUS
}

# +------------------------------------------------------------------------
# | Prints a (more or less) short help text explaining the usage of the
# | program.
# +------------------------------------------------------------------------
# | Arguments:
# |  None
# +------------------------------------------------------------------------
# | Return values:
# |  None
# +------------------------------------------------------------------------
# | Global variables used:
# |  * HTB_USAGE_LINE
# +------------------------------------------------------------------------
# | Global functions called:
# |  None
# +------------------------------------------------------------------------
# | HTB script invoked:
# |  None
# +------------------------------------------------------------------------

HTB_PRINT_USAGE()
{
  cat << EOF
$HTB_USAGE_LINE
 -h: Print this usage text
 -s: Stop and wait until the user has pressed <ENTER> to confirm the message
 -t <timeout>: Wait only for <timeout> seconds
 messagetext: Message to print
 
Exit codes:
 0: No error
 2: Aborted by signal (e.g. Ctrl+C)
 3: Error during initialisation
 4: Error while checking arguments
 5: Error during main program
 6: Timeout exceeded
EOF
}

# /////////////////////////////////////////////////////////////////////////
# // Main program
# /////////////////////////////////////////////////////////////////////////

# +------------------------------------------------------------------------
# | Variable declaration and initialisation
# +------------------------------------------------------------------------

# Basic information about this script
HTB_SCRIPT_NAME="$(basename $0)"
HTB_SCRIPT_DIR="$(pwd)/$(dirname $0)"
HTB_USAGE_LINE="$HTB_SCRIPT_NAME [-hs] [-t <timeout>] messagetext"

# Catch signals: 2=SIGINT (CTRL+C), 15=SIGTERM (simple kill)
trap "HTB_CLEANUP_AND_EXIT 2" 2 15

# Make sure that the HTB environment is loaded
if test -z "$HTB_ENVIRONMENT_INCLUDED"; then
  if test -z "$HTB_BASE_DIR"; then
    HTB_BASE_DIR="$HTB_SCRIPT_DIR/.."
  fi
  HTB_ENV_SCRIPT_PATH="$HTB_BASE_DIR/etc/htb-setenv.sh"
  if test ! -f "$HTB_ENV_SCRIPT_PATH"; then
    HTB_CLEANUP_AND_EXIT 3 "Unable to find HTB environment"
  fi
  . "$HTB_ENV_SCRIPT_PATH"
fi

# Remaining variables and resources
OPTSOK=hst:
unset STOP TIMEOUT

# Exit immediately if no tty is connected
if test -z "$HTB_TTY"; then
  HTB_CLEANUP_AND_EXIT 0
fi

# +------------------------------------------------------------------------
# | Argument processing
# +------------------------------------------------------------------------

while getopts $OPTSOK OPTION
do
  case $OPTION in
    h)
      HTB_PRINT_USAGE
      HTB_CLEANUP_AND_EXIT 0
      ;;
    s)
      STOP=1
      ;;
    t)
      TIMEOUT="$OPTARG"
      ;;
    \?)
      HTB_CLEANUP_AND_EXIT 4 "$HTB_USAGE_LINE"
      ;;
  esac
done
shift $(expr $OPTIND - 1)

if test $# -eq 0; then
  HTB_CLEANUP_AND_EXIT 4 "Invalid number of arguments"
fi

if test -z "$TIMEOUT"; then
  READ_COMMAND="read"
else
  expr $TIMEOUT + 0 >/dev/null 2>&1
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 4 "Specified timeout $TIMEOUT is not numeric"
  fi
  # Note: The "-t" option is bash specific
  READ_COMMAND="read -t $TIMEOUT"
fi

# +------------------------------------------------------------------------
# | Main program processing
# +------------------------------------------------------------------------

while test $# -gt 0; do
  echo "$1" >&2
  shift
done

if test -n "$STOP"; then
  printf "<ENTER>" >&2
  eval $READ_COMMAND
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 6
  fi
fi

HTB_CLEANUP_AND_EXIT 0
