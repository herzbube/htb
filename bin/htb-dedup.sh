#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-dedup.sh
# | Date:           17 Jul 2007
# | Description:    Remove duplicate lines from a file. The script has two
# |                 variants:
# |
# |                 1) from all lines in the file only the first occurrence is
# |                    printed out; any duplicates are discarded; this variant
# |                    is the default behaviour
# |                 2) only lines that are truly unique are printed out; if a
# |                    line occurs multiple times, it is completely ignored
# |
# |                 The caller may specify an awk expression to be used for
# |                 for determining whether a line should be considered a
# |                 duplicate. The default expression is "$0", which means
# |                 "the entire line".
# |
# | Arguments:      -h: Print a short help page
# |                 -u: Enable unique mode (i.e. mode 2)
# |                 -c <criteria>: Criteria expression (awk syntax)
# |                 [file...]: Specification of file(s) to process. Read from
# |                   stdin if no files are specified.
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
 -u: Enable unique mode, i.e. completely eliminate lines that occur more than
   2 times
 -c <criteria>: An awk expression to use as the criteria whether or not a line
   is a duplicate to a previously encountered line (default is \$0, which means
   "the entire line")
 [file...]: Specification of files to process. Reads from stdin if no files are
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
HTB_USAGE_LINE="$HTB_SCRIPT_NAME [-hu] [-c <criteria>] [file...]"

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
OPTSOK=huc:
AWK_FILE_PATH="$HTB_TMP_DIR/$HTB_SCRIPT_NAME.awk"
unset FILES UNIQUE CRITERIA

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
      UNIQUE=1
      ;;
    c)
      CRITERIA="$OPTARG"
      ;;
    \?)
      HTB_CLEANUP_AND_EXIT 4 "$HTB_USAGE_LINE"
      ;;
  esac
done
shift $(expr $OPTIND - 1)
FILES="$*"

if test -z "$CRITERIA"; then
  CRITERIA='$0'
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
# | Generate awk script
# +------------------------------------------------------------------------

mkdir -p "$HTB_TMP_DIR"
if test -z "$UNIQUE"; then
  cat << EOF >"$AWK_FILE_PATH"
BEGIN {
  FS=";"
}
{
  crit = $CRITERIA

  # If we never encountered the criteria for duplication, we can
  # print out the current line (i.e. this is the first occurrence)
  if (length(arrCrit[crit]) == 0)
  {
    arrCrit[crit] = 1
    print \$0
  }
}
EOF
else
  cat << EOF >"$AWK_FILE_PATH"
BEGIN {
  FS=";"
}
{
  crit = $CRITERIA

  # Count how many times we encountered the criteria
  arrCritCount[crit] ++
  # Remember the line
  arrContent[crit] = \$0
}
END {
  # Iterate all criteria that we encountered
  for(crit in arrCritCount)
  {
    # If we encountered the criteria more than once, we are
    # not interested in the remembered line
    if (arrCritCount[crit] > 1) { continue }

    # If we encountered the criteria exactly once, we
    # can print out the remembered line
    print arrContent[crit]
  }
}
EOF
fi

# +------------------------------------------------------------------------
# | Main program processing
# +------------------------------------------------------------------------

for FILE in $FILES; do
  if test "$FILE" = "-"; then
    unset FILE
  fi
  if test -n "$PRINT_LEADIN_FILENAME"; then
    echo "De-duplicating file $FILE"
  fi
  awk -f "$AWK_FILE_PATH" "$FILE"
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 5 "Error while processing $FILE"
  fi
done

HTB_CLEANUP_AND_EXIT 0
