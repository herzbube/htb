#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-rename.sh
# | Date:           01 Jan 2011
# | Description:    Rename files by performing a search & replace operation on
# |                 the name of all specified files.
# |
# | Arguments:      -h: Print a short help page
# |                 -r: Recursively operate on directories
# |                 <search>: Search pattern (sed syntax)
# |                 <replace>: Replace pattern (sed syntax)
# |                 [file...]: Specification of file(s) to process. Processes
# |                   all files in the current working directory if no files
# |                   are specified.
# |
# | Exit codes:     0: No error
# |                 2: Aborted by signal (e.g. Ctrl+C)
# |                 3: Error during initialisation
# |                 4: Error while processing arguments
# |                 5: Error during main program
# |
# | Dependencies:   htb-msg.sh
# |
# | TODO            Cannot handle "." or ".." as the file argument. Cannot
# |                 handle a relative path that starts with "." or "..".
# |                 Possibly more.
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
 -r: Recursively operate on directories
 <search>: Search pattern (sed syntax)
 <replace>: Replace pattern (sed syntax)
 [file...]: Specification of file(s) to process. Process all files in the
   current working directory if no files are specified.

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
HTB_USAGE_LINE="$HTB_SCRIPT_NAME [-hr] <search> <replace> [file...]"

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
OPTSOK=hr
unset RECURSIVE SEARCH REPLACE FILES

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
    r)
      RECURSIVE="$OPTARG"
      ;;
    \?)
      HTB_CLEANUP_AND_EXIT 4 "$HTB_USAGE_LINE"
      ;;
  esac
done
shift $(expr $OPTIND - 1)
FILES="$*"

if test $# -lt 2; then
  HTB_CLEANUP_AND_EXIT 4 "$HTB_USAGE_LINE"
fi

SEARCH="$1"
REPLACE="$2"

shift 2
if [ $# -eq 0 ]
then
   set .* *
fi

# +------------------------------------------------------------------------
# | Main program processing
# +------------------------------------------------------------------------

while test $# -gt 0; do
  OLD_NAME="$1"
  shift 1

  if test "$OLD_NAME" = "." -o "$OLD_NAME" = ".."; then
    continue
  fi

  if test -n "$RECURSIVE" -a -d "$OLD_NAME"; then
    echo "Descending into directory $OLD_NAME..."
    cd "$OLD_NAME"
    $HTB_SCRIPT_NAME -r -- "$SEARCH" "$REPLACE" .* *
    cd -
  fi

  NEW_NAME=$(echo "$OLD_NAME" | sed -e "s/$SEARCH/$REPLACE/g")
  if test "$OLD_NAME" = "$NEW_NAME"; then
    continue
  fi

  echo "Renaming $OLD_NAME to $NEW_NAME..."
  mv -- "$OLD_NAME" "$NEW_NAME"
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 5 "Error while renaming $FILE"
  fi
done

HTB_CLEANUP_AND_EXIT 0
