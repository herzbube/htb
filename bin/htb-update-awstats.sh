#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-backup.sh
# | Date:           13 Jul 2011
# | Description:    Creates backup copies of various system folders. This script
# |                 is tailored for backing up my private Debian system, but
# |                 there remains a slight chance that someone else could find
# |                 it a useful source of inspiration.
# |
# | Arguments:      -h: Print a short help page
# |
# | Exit codes:     0: No error
# |                 2: Aborted by signal (e.g. Ctrl+C)
# |                 3: Error during initialisation
# |                 4: Error while processing arguments
# |                 5: Error during main program
# |
# | Dependencies:   htb-msg.sh
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
# |  * HTB_TMP_DIR
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

  if test -f "$LOCK_FILE"; then
    rm -f "$LOCK_FILE"
  fi

  if test -d "$HTB_TMP_DIR"; then
    rm -rf "$HTB_TMP_DIR"
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

Exit codes:
 0: No error
 2: Aborted by signal (e.g. Ctrl+C)
 3: Error during initialisation
 4: Error while checking arguments
 5: Error during main program
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
HTB_SCRIPT_DIR="$(dirname $0)"
case "$HTB_SCRIPT_DIR" in
  /*) ;;
  *)  HTB_SCRIPT_DIR="$(pwd)/$HTB_SCRIPT_DIR" ;;
esac
HTB_USAGE_LINE="$HTB_SCRIPT_NAME [-h]"

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

CONF_DIR=/etc/awstats
CONF_FILE_PREFIX="awstats."
CONF_FILE_POSTFIX=".conf"
CONF_FILES_TO_SKIP="awstats.conf"
AWSTATS_EXECUTABLE="/usr/lib/cgi-bin/awstats.pl"

# Remaining variables and resources
OPTSOK=h

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
    \?)
      HTB_CLEANUP_AND_EXIT 4 "$HTB_USAGE_LINE"
      ;;
  esac
done
shift $(expr $OPTIND - 1)

if test $# -ne 0; then
  HTB_CLEANUP_AND_EXIT 4 "$HTB_USAGE_LINE"
fi

# +------------------------------------------------------------------------
# | Main program processing
# +------------------------------------------------------------------------

if test ! -d "$CONF_DIR"; then
  HTB_CLEANUP_AND_EXIT 5 "Configuration directory $CONF_DIR does not exist"
fi
cd "$CONF_DIR"

if test ! -x "$AWSTATS_EXECUTABLE"; then
  HTB_CLEANUP_AND_EXIT 5 "The awstats executable $AWSTATS_EXECUTABLE does not exist or is not executable"
fi

for CONF_FILE in ${CONF_FILE_PREFIX}*${CONF_FILE_POSTFIX}
do
  SKIP_CONF_FILE=0
  for CONF_FILE_TO_SKIP in $CONF_FILES_TO_SKIP
  do
    if test "$CONF_FILE" = "$CONF_FILE_TO_SKIP"; then
      SKIP_CONF_FILE=1
      break
    fi
  done
  if test $SKIP_CONF_FILE -eq 1; then
    continue
  fi

  VIRTUAL_HOST_NAME=$(echo "$CONF_FILE" | sed -e 's/^'$CONF_FILE_PREFIX'//' -e 's/'$CONF_FILE_POSTFIX'$//')
  $AWSTATS_EXECUTABLE -config="$VIRTUAL_HOST_NAME" -update >/dev/null
done


HTB_CLEANUP_AND_EXIT 0
