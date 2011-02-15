#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-yesterday.sh
# | Date:           12 Feb 2011
# | Description:    Calculate and print the specified date minus 1 day
# |
# | Arguments:      -h: Print a short help page
# |                 date: Specification of date in format dd.mm.yyyy
# |
# | Exit codes:     0: No error
# |                 2: Aborted by signal (e.g. Ctrl+C)
# |                 3: Error during initialisation
# |                 4: Error while processing arguments
# |                 5: Error during main program
# |
# | Dependencies:   htb-msg.sh
# |
# | TODO            This program is not terribly robust, notably
# |                 * It is not possible to specify dates before 1900. Other
# |                   dates near 1900/1901 may also not be accepted.
# |                 * It is possible to specify 29.02 even though the year is
# |                   not a leap year. Other invalid dates may also be possible.
# |                 The reason for this is that the program uses the Perl
# |                 function POSIX::mktime(). Other date-related Perl modules
# |                 may be more robust, but they might not be present on all
# |                 systems. The POSIX module, on the other hand, is supplied
# |                 with the standard distribution of Perl. It is therefore
# |                 reasonable to expect that the module is present on all but
# |                 but the most stripped-down installations. If the system is
# |                 not POSIX compliant, then of course this program will fail.
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
 date: Specification of date in format dd.mm.yyyy

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
HTB_USAGE_LINE="$HTB_SCRIPT_NAME [-h] date"

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
PERL_FILE_PATH="$HTB_TMP_DIR/$HTB_SCRIPT_NAME.pl"
unset TODAY_DATE

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
  HTB_CLEANUP_AND_EXIT 4 "No date specified"
fi
if test $# -gt 1; then
  HTB_CLEANUP_AND_EXIT 4 "Too many arguments"
fi
TODAY_DATE="$1"

# +------------------------------------------------------------------------
# | Generate perl script
# +------------------------------------------------------------------------

mkdir -p "$HTB_TMP_DIR"
cat << EOF >"$PERL_FILE_PATH"
use POSIX;

# Check if the specified today date contains illegal characters
\$today_date = "$TODAY_DATE";
if (\$today_date =~ /[^0-9\\.]/) { exit(1); }

# Separate original date into its components -> must result in 3 components
@date_parts = split(/\\./, \$today_date);
if (scalar(@date_parts) != 3) { exit(1); }

# Original date (in local time)
\$sec=0;
\$min=0;
\$hour=0;
\$mday=@date_parts[0];
\$mon=@date_parts[1];
\$year=@date_parts[2];

# Perform basic validation. Must do this ourselves because POSIX::mktime() is
# *very* forgiving about its arguments (e.g. it accepts arbitrary numbers for
# month or day)
if (\$year < 1900) { exit(1); }
if (\$mon < 1 || \$mon > 12) { exit(1); }
@max_month_days = (31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
if (\$mday < 1 || \$mday > \$max_month_days[\$mon - 1]) { exit(1); }

# Convert to epoch
# Note: Months start at 0, and year is given in years since 1900
\$mon--;
\$year -= 1900;
\$time_t = POSIX::mktime(\$sec, \$min, \$hour, \$mday, \$mon, \$year);
if (not defined(\$time_t)) { exit(1); }

# Subtract number of seconds worth 1 day
\$time_t -= 24 * 60 * 60;

# Convert back to local time
# Note: Again, month and year must be re-calculated into human terms
(\$sec, \$min, \$hour, \$mday, \$mon, \$year, \$wday, \$yday, \$isdst) = localtime(\$time_t);
\$mon++;
\$year += 1900;

# Print formatted date
printf("%02d.%02d.%04d", \$mday, \$mon, \$year);
EOF

# +------------------------------------------------------------------------
# | Main program processing
# +------------------------------------------------------------------------

YESTERDAY_DATE="$(perl "$PERL_FILE_PATH")"
if test $? -ne 0; then
  HTB_CLEANUP_AND_EXIT 5 "Error while calculating date"
fi
echo "$YESTERDAY_DATE"

HTB_CLEANUP_AND_EXIT 0
