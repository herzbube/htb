#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-chkevent.sh
# | Date:           01 Jan 2011
# | Description:    Checks whether the current date/time matches the given
# |                 crontab-style date/time specification. Prints "1" if there
# |                 is a match, or "0" if there is no match.
# |
# | Arguments:      -h: Print a short help page
# |                 timespec: Time specification in crontab format, e.g.
# |                   "0,20,40 * * * *"
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
 -h: Print this usage text
 timespec: Time specification in crontab format, e.g. "0,20,40 * * * *"

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
HTB_USAGE_LINE="$HTB_SCRIPT_NAME [-h] timespec"

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
OPTSOK=h
AWK_FILE_PATH="$HTB_TMP_DIR/$HTB_SCRIPT_NAME.awk"
unset TIMESPEC

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

if test $# -eq 0; then
  HTB_CLEANUP_AND_EXIT 4 "No timespec specified"
fi

if test $# -ne 1; then
  HTB_CLEANUP_AND_EXIT 4 "More than 1 timespec specified"
fi

TIMESPEC="$1"

# +------------------------------------------------------------------------
# | Generate awk script
# +------------------------------------------------------------------------

mkdir -p "$HTB_TMP_DIR"
cat << EOF >"$AWK_FILE_PATH"
BEGIN {
  # Initialisation
  exitValue = 0

  # Current date/time
  "date +%d-%m-%H-%M-%w" | getline DATE
  i = split(DATE, z, "-")
  nowday = z[1]
  nowmonth = z[2]
  nowhour= z[3]
  nowmin = z[4]
  nowweekday = z[5]
}
{
  # There must be exactly 5 fields
  i = split(\$0, z, " " )
  if (i != 5) { exitValue = 1; exit exitValue }

  result_mins = analyze_field(z[1], nowmin)
  result_hours = analyze_field(z[2], nowhour)
  result_days = analyze_field(z[3], nowday)
  result_months = analyze_field(z[4], nowmonth)
  result_weekdays = analyze_field(z[5], nowweekday)

  # Any errors?
  if (result_mins == 3 || result_hours == 3 || result_days == 3 || result_months == 3 || result_weekdays == 3)
  {
    exitValue = 1; exit exitValue
  }

  # Special treatment of the two day-specs:
  # * If one of the fields only has an asterisk, the other field takes
  #   precedence (or rather, the asterisk'ed field is set to the same value
  #   as the field taking precedence)
  # * If none of the fields was specified with an asterisk, both fields retain
  #   their value and it is sufficient for either one to match
  # * If both fields were specified with an asterisk, they both always match
  #   (as usual for asterisk'ed fields)
  if (result_days == 2 && result_weekdays != 2)
  {
    result_days = result_weekdays
  }
  else if (result_days != 2 && result_weekdays == 2)
  {
     result_weekdays = result_days
  }

  # All fields must match the current date. See above for special treatment of
  # the two day-specs.
  if (result_mins && result_hours && result_months && (result_days || result_weekdays))
  {
    result = 1
  }
  else { result = 0 }

  print result
}
END {
  # exit statements in the BEGIN or the main processing section jumps to this
  # end section -> we have to repeat the exit statement here
  exit exitValue
}

# +------------------------------------------------------------------------
# | Compares one of the 5 fields to the current date/time.
# +------------------------------------------------------------------------
# | Arguments:
# |  * field: Timespec value to check
# |  * val2compare: Current date/time value to compare to
# +------------------------------------------------------------------------
# | Return values:
# |  * 0: No match
# |  * 1: Match (normal)
# |  * 2: Match (asterisk). Required because of the two day-specs
# |  * 3: Format error
# +------------------------------------------------------------------------
function analyze_field(field, val2compare)
{
  # A single asterisk always matches
  if (field == "*") { return 2 }

  # An asterisk with other stuff inside the value is an error
   if (field ~ /\*/) { return 3 }

  # A list must separate its entries using ","
  no_of_items = split(field, item, ",")
  for (i = 1; i <= no_of_items; i++)
  {
    # Check for a range
    j = split( item[i], range, "-" )
    # If it's not a simple number (i.e. not a range, j==1) and not a range
    # (j==2), it's an error
    if (j < 1 || j > 2) { return 3 }

    # Simple number: Value must match exactly
    if      (j == 1 && (range[1] + 0) == (val2compare + 0)) { return 1 }
    # Range: Value must be inside the range (duh!)
    else if (j == 2 && (range[1] + 0) <= (val2compare + 0) && (range[2] + 0) >= (val2compare + 0)) { return 1 }
  }

  # No match
  return 0
}
EOF

# +------------------------------------------------------------------------
# | Main program processing
# +------------------------------------------------------------------------

echo "$TIMESPEC" | awk -f "$AWK_FILE_PATH"
if test $? -ne 0; then
  HTB_CLEANUP_AND_EXIT 5 "Illegal timespec"
fi

HTB_CLEANUP_AND_EXIT 0
