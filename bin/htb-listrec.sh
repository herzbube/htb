#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-listrec.sh
# | Date:           01 Jan 2011
# | Description:    List the fields of a record (or line).
# |
# | Arguments:      -h: Print a short help page
# |                 [-d <fs>]: Field delimiter. The default is a semicolon. Use
# |                   the same syntax as you would for awk's -F argument.
# |                 [-l <line>]: Record (=line) number to list. The default is
# |                   the first line. Use "$" to specify the last line.
# |                 [file...]: Specification of file(s) to process. Read from
# |                   stdin if no files are specified. List the same record for
# |                   each file if more than 1 file is specified.
# |
# | Exit codes:     0: No error
# |                 2: Aborted by signal (e.g. Ctrl+C)
# |                 3: Error during initialisation
# |                 4: Error while processing arguments
# |                 5: Error during main program
# |
# | Dependencies:   htb-msg.sh
# |                 htb-lcut.sh
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
 [-d <fs>]: Field delimiter. The default is a semicolon. Use the same syntax as
   you would for awk's -F argument.
 [-l <line>]: Record (=line) number to list. The default is the first line.
   Use "$" to specify the last line.
 [file...]: Specification of files to process. Read from stdin if no files are
   specified. List the same record for each file if more than 1 file is
   specified.

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
HTB_SCRIPT_DIR="$(pwd)/$(dirname $0)"
HTB_USAGE_LINE="$HTB_SCRIPT_NAME [-h] [-d <fs>] [-l <line>] [file...]"

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
OPTSOK=hd:l:
unset DELIMITER LINE FILES PRINT_LEADIN_FILENAME

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
    d)
      DELIMITER="$OPTARG"
      ;;
    l)
      LINE="$OPTARG"
      ;;
    \?)
      HTB_CLEANUP_AND_EXIT 4 "$HTB_USAGE_LINE"
      ;;
  esac
done
shift $(expr $OPTIND - 1)
FILES="$*"

if test -z "$DELIMITER"; then
  DELIMITER=";"
fi

if test -z "$LINE"; then
  LINE=1
fi

if test "$LINE" != "$"; then
  expr $LINE + 1 >/dev/null 2>&1
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 4 "Line number is not numeric"
  fi
fi

if test -z "$FILES"; then
  FILES="-"
else
  NUMBER_OF_FILES=0
  for FILE in $FILES; do
    if test ! -f "$FILE"; then
      HTB_CLEANUP_AND_EXIT 4 "Specified file $FILE does not exist"
    fi
    NUMBER_OF_FILES=$(expr $NUMBER_OF_FILES + 1)
  done
  if test $NUMBER_OF_FILES -gt 1; then
    PRINT_LEADIN_FILENAME=1
  fi
fi

# +------------------------------------------------------------------------
# | Main program processing
# +------------------------------------------------------------------------

for FILE in $FILES; do
  if test "$FILE" = "-"; then
    unset FILE
  fi
  if test -n "$PRINT_LEADIN_FILENAME"; then
    echo "Cutting $LINES from $FILE"
  fi
  htb-lcut.sh -l $LINE $FILE | awk -F"$DELIMITER" '{nrOfFields = split($0, f, FS); for (i=1; i<=nrOfFields; i++) { printf("%3s  %s\n", i, f[i])}}'
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 5 "Error while processing $FILE"
  fi
done

HTB_CLEANUP_AND_EXIT 0
