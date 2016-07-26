#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-sa-learn.sh
# | Date:           13 Jul 2011
# | Description:    Trains the spam Bayes database of the currently logged in
# |                 system user. Uses the SpamAssassin program sa-learn to
# |                 do the training. The Maildir folders that are used for
# |                 training are hardcoded:
# |
# |                   $HOME/Maildir/.Junk.Training-ham   (contains ham)
# |                   $HOME/Maildir/.Junk.Training-spam  (contains spam)
# |
# |                 This script is intended to be run by cron, but it can
# |                 also be invoked manually on the command line. The script
# |                 sends a message to syslog (using the command line utility
# |                 logger) whenever training occurs.
# |
# | Arguments:      -h: Print a short help page
# |
# | Exit codes:     0: No error
# |                 2: Aborted by signal (e.g. Ctrl+C)
# |                 3: Error during initialisation
# |                 4: Error while processing arguments
# |                 5: This program is already running for the current user
# |                 6: A prerequisite could not be found
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

# Maildirs
MAIL_DIR="Maildir"
TRAINING_HAM_DIR=".Junk.Training-ham"
TRAINING_SPAM_DIR=".Junk.Training-spam"
TRAINED_AS_HAM_DIR="."
TRAINED_AS_SPAM_DIR=".Junk.Incoming"

# Programs
SA_LEARN_BIN=/usr/bin/sa-learn

# Other variables
LOCK_FILE="$HOME/$(basename $0).$LOGNAME.pid"

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

# Check if this program is already running for the current user
if test -f "$LOCK_FILE"; then
  HTB_CLEANUP_AND_EXIT 5
fi

# Sanity checks
for BIN in "$SA_LEARN_BIN"
do
  which "$BIN" >/dev/null 2>&1
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 6 "$BIN could not be found"
  fi
done

# Create lock file. From now on, do not return without removing the file
echo $$ >"$LOCK_FILE"

# Process all messages
for MESSAGE_TYPE in ham spam
do
  if test "$MESSAGE_TYPE" = "ham"; then
    TRAINING_BASE_DIR="$HOME/$MAIL_DIR/$TRAINING_HAM_DIR"
  elif test "$MESSAGE_TYPE" = "spam"; then
    TRAINING_BASE_DIR="$HOME/$MAIL_DIR/$TRAINING_SPAM_DIR"
  else
    continue
  fi

  for SUB_DIR in new cur
  do
    TRAINING_DIR="$TRAINING_BASE_DIR/$SUB_DIR"
    if test ! -d "$TRAINING_DIR"; then
      echo "Training directory not found: $TRAINING_DIR"
      continue
    fi

    # Learn/re-learn messages
    echo "Learning $MESSAGE_TYPE from $TRAINING_DIR for $USER" 2>&1 | logger
    $SA_LEARN_BIN "--$MESSAGE_TYPE" "$TRAINING_DIR" 2>&1 | logger
  done
done


HTB_CLEANUP_AND_EXIT 0
