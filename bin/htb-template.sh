#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-foo.sh
# | Date:           01 Jan 2011
# | Description:    foo
# |
# | Arguments:      -h: Print a short help page
# |
# | Exit codes:     0: No error
# |                 1: Aborted by user interaction
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
# | Removes temporary files and exits the program using the given exit
# | code.
# +------------------------------------------------------------------------
# | Arguments:
# |  * Exit code
# |  * Error message: This argument is optional. If specified, and if connected
# |    to a tty, the error message is printed to stderr using htb-msg.sh.
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
# |  * htb-msg.sh
# +------------------------------------------------------------------------

HTB_CLEANUP_AND_EXIT()
{
  typeset EXIT_STATUS=$1
  typeset ERROR_MESSAGE="$2"

  # Print message to screen only if a tty is connected
  if test -n "$ERROR_MESSAGE"; then
    if test -n "$HTB_TTY"; then
      htb-msg.sh "$HTB_SCRIPT_NAME: $ERROR_MESSAGE"
    fi
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
 -u d|m|y|h|i|s: Unit to calculate (days, months, years, hours, minutes,
   seconds)
 -s <start>: Start date, format dd.mm.yyyy-hh:mm:ss, or start field in <file>
 -e <end>: End date, format dd.mm.yyyy-hh:mm:ss, or end field in <file>
 -d <fs>: Field delimiter, if files are processed
 [file...]: Specification of file(s) to process. Specify "-" to read from
   stdin. If no files are specified, assume that the -s and -e arguments are
   used to specify dates.

Exit codes:
 0: No error
 1: Aborted by user interaction
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
HTB_SCRIPT_DIR="$(pwd)/$(dirname $0)"
HTB_USAGE_LINE="$HTB_SCRIPT_NAME [-h] [-m d|m|y|h|i|s] [-v <von>] [-b <bis>] [-d <fs>] [<file> ...]"

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
TMP_FILE_PATH="$HTB_TMP_DIR/$HTB_SCRIPT_NAME.tmp"
OPTSOK=hu:s:e:d:
unset UNIT START END DELIMITER FILES

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
    u)
      UNIT="$OPTARG"
      ;;
    s)
      START="$OPTARG"
      ;;
    e)
      END="$OPTARG"
      ;;
    d)
      DELIMITER="$OPTARG"
      ;;
    \?)
      HTB_CLEANUP_AND_EXIT 4 "$HTB_USAGE_LINE"
      ;;
  esac
done
shift $(expr $OPTIND - 1)
FILES="$*"

if test -z "$UNIT"; then
  UNIT=i   # minutes
fi

case $UNIT in
  [dmyhis])
    ;;
  *)
    HTB_CLEANUP_AND_EXIT 4 "Invalid unit"
    ;;
esac

if test -z "$DELIMITER"; then
  DELIMITER=";"
fi

# Determine data source: 0 = files, 1 = parameters
if test -n "$FILES"; then
  DATA_SOURCE=0
  # Unsetting the variable causes awk to read from stdin
  if test $FILES = "-" ; then
    unset FILES
  fi
else
  DATA_SOURCE=1
  FILES="$TMP_FILE_PATH"
  # HTB_TMP_FILE_PATH must contain something, otherwise awk processing will fail
  mkdir -p "$HTB_TMP_DIR"
  echo "dummy" >"$TMP_FILE_PATH"
fi

# +------------------------------------------------------------------------
# | Main program processing
# +------------------------------------------------------------------------

export UNIT START END DATA_SOURCE
# TODO: Spaces in file names will not work
awk -F"$DELIMITER" -f "$AWK_FILE_PATH" $FILES
RETURN_VALUE=$?
if test $RETURN_VALUE -ne 0; then
  HTB_CLEANUP_AND_EXIT 5 "Error $RETURN_VALUE while processing input"
fi

HTB_CLEANUP_AND_EXIT 0
