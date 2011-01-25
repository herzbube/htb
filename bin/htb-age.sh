#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-age.sh
# | Date:           01 Jan 2011
# | Description:    Calculates the difference between two dates.
# |
# | Arguments:      -h: Print a short help page
# |                 [-u d|m|y|h|i|s]: Unit to calculate (days, months (1 month =
# |                   30 days), years (1 year = 365 days), hours, minutes,
# |                   seconds). The default is minutes.
# |                 -s <start>: Start date, format dd.mm.yyyy-hh:mm:ss, or
# |                   start field in <file>. The default is 01.01.1970-00:00:00.
# |                 -e <end>: End date, format dd.mm.yyyy-hh:mm:ss, or end
# |                   field in <file>. The default is <now>.
# |                 -d <fs>: Field delimiter, if files are processed. The
# |                   default is a semicolon.
# |                 [file...]: Specification of file(s) to process. Specify "-"
# |                   to read from stdin. If no files are specified, assume
# |                   that the -s and -e arguments are used to specify dates.
# |
# | Exit codes:     0: No error
# |                 2: Aborted by signal (e.g. Ctrl+C)
# |                 3: Error during initialisation
# |                 4: Error while processing arguments
# |                 5: Error during main program
# |
# | Dependencies:   htb-msg.sh
# |
# | TODO            Calculation may not always work correctly. Error handling
# |                 most assuredly does not always work correctly (e.g. start
# |                 date > end date is not handled)
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
 [-u d|m|y|h|i|s]: Unit to calculate (days, months (1 month = 30 days), years
   (1 year = 365 days), hours, minutes, seconds). The default is minutes.
 -s <start>: Start date, format dd.mm.yyyy-hh:mm:ss, or start field in <file>.
   The default is 01.01.1970-00:00:00.
 -e <end>: End date, format dd.mm.yyyy-hh:mm:ss, or end field in <file>.
   The default is <now>.
 -d <fs>: Field delimiter, if files are processed. The default is a semicolon.
 [file...]: Specification of file(s) to process. Specify "-" to read from
   stdin. If no files are specified, assume that the -s and -e arguments are
   used to specify dates.

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
HTB_USAGE_LINE="$HTB_SCRIPT_NAME [-h] [-u d|m|y|h|i|s] [-s <start>] [-e <end>] [-d <fs>] [file...]"

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
OPTSOK=hu:s:e:d:
AWK_FILE_PATH="$HTB_TMP_DIR/$HTB_SCRIPT_NAME.awk"
TMP_FILE_PATH="$HTB_TMP_DIR/$HTB_SCRIPT_NAME.tmp"
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
# | Generate awk script
# +------------------------------------------------------------------------

mkdir -p "$HTB_TMP_DIR"
cat << EOF >"$AWK_FILE_PATH"
# The input for this script is a line with two dates, separated by a space
# character. The date format must be
#   dd.mm.yyyy-hh:mm:ss
#
# If the date part is not specified, the script assumes "01.01.1970" as the
# default. Default for the time part is "00:00:00".
#
# If the year is relevant to the calculation, it must be specified using 4
# digits, otherwise leap years will not be calculated correctly. Other date/time
# parts do not need to be prefixed with "0".
#
# Internally the script always calculates the difference between dates in
# seconds. The environment variable $UNIT determines the unit of the actual
# output: d=days, m=months (1 month = 30 days), y=years (1 year = 365 days),
# h=hours, i=minutes, s=seconds. The default is minutes.
#
# WARNING: There is no check whether dates/times are valid (e.g. minutes = 0-60)
# or whether the start date is behind the end date.
#
# Error handling:
# - If the input comes from file(s) and there is an error, the script exits
#   normally but prints a negative value that should then be used as the actual
#   exit code by the invoking shell script
# - If the input comes from start/end variables and there is an error, the
#   script exits using the actual exit code that should also be used by the
#   invoking shell script
# - Exit codes used:
#    1/-1: Invalid unit
#    3/-3: Invalid date/time formatting (more than "-" characters)
#    4/-4: Invalid date/time formatting (neither "." nor ":" character)
#    5/-5: Invalid date part formatting (not 3 fields)
#    6/-6: Invalid time part formatting (not 3 fields)
#    7/-7: Difference < 0 (e.g. if start date is behind the end date

BEGIN {
  # Default exit code
  exitValue = 0

  # Arguments from shell script
  unit = "$UNIT"
  startDate = "$START"
  endDate = "$END"
  dataSource = "$DATA_SOURCE"

  # Use minutes if unit is not specified
  if (length(unit) == 0) { unit = "i" }
  # Is unit valid?
  if (unit !~ /^[dmyhis]\$/) { output(dataSource, -1) }
  # Defaults for start and end date
  if (length(startDate) == 0) { default[ 1 ] = "01.01.1970-00:00:00" }
  if (length(endDate) == 0) { "date '+%d.%m.%Y-%H:%M:%S'" | getline default[ 2 ] }

  # Days per month
  dom[1] = 31; dom[2] = 28; dom[3] = 31; dom[4]  = 30; dom[5]  = 31; dom[6]  = 30
  dom[7] = 31; dom[8] = 31; dom[9] = 30; dom[10] = 31; dom[11] = 30; dom[12] = 31
}

{
  # Fill input fields
  # dataSource=0: Input is coming from file(s), dataSource=1: Input is coming
  # from startDate/endDate variables
  if      (length( default[1] ) > 0) { dat[1] = default[1] }
  else if (dataSource == 1)          { dat[1] = startDate }
  else                               { dat[1] = \$startDate }
  if      (length( default[2] ) > 0) { dat[2] = default[2] }
  else if (dataSource == 1)          { dat[2] = endDate }
  else                               { dat[2] = \$endDate }

  # Streamline everything to the same format
  for (i = 1; i <= 2; i++)
  {
    # Cut date part from time part
    j = split(dat[i], z1, "-")
    if (j == 0 || j > 2) { output(dataSource, -3) }
    # Assume default values for missing parts
    else if (j == 1)
    {
      if      (z1[ 1] ~ /\./) { z1[2] = "00:00:00" }
      else if (z1[ 1] ~ /:/)  { z1[2] = z1[1]; z1[1] = "01.01.1970" }
      else                    { output(dataSource, -4) }
    }
    # Split date part
    j = split(z1[1], z2, ".")
    if (j != 3) { output(dataSource, -5) }
    dd[i] = z2[1] + 0; mm[i] = z2[2] + 0; yy[i] = z2[3] + 0
    # Split time part
    j = split(z1[2], z2, ":")
    if (j != 3) { output(dataSource, -6) }
    hh[i] = z2[1] + 0; ii[i] = z2[2] + 0; ss[i] = z2[3]+0
  }

  diffDD = 0
  # Number of days if start and end year are the same
  if (yy[1] == yy[2] ) { diffDD += calcDays(dd[1], mm[1], dd[2], mm[2], yy[1]) }
  else
  {
    # Calculate number of days of those years that lie between start and end
    for (i = yy[1] + 1; i <= yy[2] - 1; i++ )
    {
      # Leap year?
      if (i % 4 == 0) { diffDD += 366 }
      else            { diffDD += 365 }
    }
    # Days of partial startDate year
    diffDD += calcDays(dd[1], mm[1], 31, 12, yy[1] )
    # Days of partial endDate year
    diffDD += calcDays(1, 1, dd[2], mm[2], yy[2] )
    # Re-add 1 day because one day too many was lost by the *TWO* subtraction
    # calculations above
    diffDD ++
  }

  # Determine whether less than 1 day is between start and end time
  if ( hh[1] > hh[2] ) { flag = 1 }
  else if (hh[1] == hh[2] && ii[1] > ii[2] ) { flag = 1 }
  else if (hh[1] == hh[2] && ii[1] == ii[2] && ss[1] > ss[2] ) { flag = 1 }
  else { flag = 0 }

  diffSS = (diffDD - flag) * 24 * 3600
  if (flag == 1)
  {
    # Seconds of partial startDate day
    diffSS += calcSecs(hh[1], ii[1], ss[1], 23, 59, 59)
    # Seconds of partial endDate day
    diffSS += calcSecs(0, 0, 0, hh[2], ii[2], ss[2])
    # Re-add 1 second because one second too many was lost by the *TWO*
    # subtraction calculations above
    diffSS ++
  }
  else
  {
    # Difference between stat and end times
    diffSS += calcSecs(hh[1], ii[1], ss[1], hh[2], ii[2], ss[2])
  }

  if (diffSS < 0) { output(dataSource, -7) }

  # Calculate result value depending on the requested unit (years have 365
  # days, months have 30 days)
  if      (unit == "y") { diffVal = diffSS / (60 * 60 * 24 * 365) }
  else if (unit == "m") { diffVal = diffSS / (60 * 60 * 24 * 30) }
  else if (unit == "d") { diffVal = diffSS / (60 * 60 * 24) }
  else if (unit == "h") { diffVal = diffSS / (60 * 60) }
  else if (unit == "i") { diffVal = diffSS / 60 }
  else if (unit == "s") { diffVal = diffSS }

  # Chop fractions
  diffVal = int(diffVal)
  output( dataSource, diffVal )
}

END {
  # exit statements in the BEGIN or the main processing section jumps to this
  # end section -> we have to repeat the exit statement here
  exit exitValue
}

# +------------------------------------------------------------------------
# | Calculates the number of days between two dates of the same year. The
# | year must be passed with 4 digits so that leap year calculation works
# | correctly.
# +------------------------------------------------------------------------
# | Arguments:
# |  * startDateDD: two digit "day of month" of the startDate
# |  * startDateMM: two digit month of the startDate
# |  * endDateDD: two digit "day of month" of the startDate
# |  * endDateMM: two digit month of the endDate
# |  * year: four digit year (both for startDate and endDate)
# +------------------------------------------------------------------------
# | Return values:
# |  * Number of days between the two dates
# +------------------------------------------------------------------------
function calcDays(startDateDD, startDateMM, endDateDD, endDateMM, year)
{
  days = 0
  if (startDateMM == endDateMM) { days = endDateDD - startDateDD }
  else
  {
    for (i = startDateMM + 1; i <= endDateMM - 1; i++) { days += dom[i] }
    days += dom[startDateMM] - startDateDD
    days += endDateDD
    # If it's a leap year and startDate month is either January or February
    # -> number of days + 1
    if ( year % 4 == 0 && startDateMM <= 2 ) { days ++ }
  }
  return days
}

# +------------------------------------------------------------------------
# | Calculates the number of seconds between two times of the same day.
# +------------------------------------------------------------------------
# | Arguments:
# |  * startDateHH: two digit hour value of the startDate
# |  * startDateII: two digit minute value of the startDate
# |  * startDateSS: two digit second value of the startDate
# |  * endDateHH: two digit hour value of the endDate
# |  * endDateII: two digit minute value of the endDate
# |  * endDateSS: two digit second value of the endDate
# +------------------------------------------------------------------------
# | Return values:
# |  * Number of seconds between the two times
# +------------------------------------------------------------------------
function calcSecs(startDateHH, startDateII, startDateSS, endDateHH, endDateII, endDateSS)
{
  seconds = 0
  if (startDateHH == endDateHH)
  {
    # If hour and minute are the same -> difference between seconds
    if (startDateII == endDateII) { seconds = endDateSS - startDateSS }
    # Otherwise seconds of the in-between minutes, plus seconds of partial
    # minutes
    else { seconds += 60 * (endDateII - startDateII - 1) + (60 - startDateSS) + endDateSS }
  }
  else
  {
    # Seconds of the in-between hours
    seconds += 3600 * (endDateHH - startDateHH - 1)
    # Seconds of the partial startDate hour
    seconds += 60 * (60 - startDateII - 1) + (60 - startDateSS)
    # Seconds of the partial endDate hour
    seconds += 60 * endDateII + endDateSS
  }
  return seconds
}

# +------------------------------------------------------------------------
# | Print result of a calculation. Depending on the dataSource (global value)
# |  * the result is appended to the existing line ($0). This applies even
# |    if the result is an error value (<0)
# |  * the result is printed to stdout (if it is not an error value), or
# |    the result is used as exit code to abort the program (if it is an error
# |    value)
# +------------------------------------------------------------------------
# | Arguments:
# |  * outputValue: result value
# +------------------------------------------------------------------------
# | Return values:
# |  None
# +------------------------------------------------------------------------
function output(outputMode, outputValue)
{
  # dataSource=0: Input comes from file(s) -> append to line
  # dataSource=1: Input comes from startDate/endDate variables -> print to stdout
  if (dataSource == 1)
  {
    if (outputValue < 0) { exitValue = -outputValue; exit exitValue }
    else                 { print outputValue }
  }
  else
  {
    print \$0 "" FS "" outputValue
    if (outputValue < 0) { next }
  }
}
EOF


# +------------------------------------------------------------------------
# | Main program processing
# +------------------------------------------------------------------------

# TODO: Spaces in file names will not work
awk -F"$DELIMITER" -f "$AWK_FILE_PATH" $FILES
RETURN_VALUE=$?
if test $RETURN_VALUE -ne 0; then
  HTB_CLEANUP_AND_EXIT 5 "Error $RETURN_VALUE while processing input"
fi

HTB_CLEANUP_AND_EXIT 0
