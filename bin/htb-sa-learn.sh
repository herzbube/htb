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
# |                 5: This program is already running for the current user
# |                 6: A prerequisite could not be found
# |                 7: Some error related to temporary files occurred
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

# Maildirs
MAIL_DIR="Maildir"
TRAINING_HAM_DIR=".Junk.Training-ham"
TRAINING_SPAM_DIR=".Junk.Training-spam"
TRAINED_AS_HAM_DIR="."
TRAINED_AS_SPAM_DIR=".Junk.Incoming"

# Programs
SA_LEARN_BIN=/usr/bin/sa-learn
SPAMC_BIN=/usr/bin/spamc
MAILDROP_BIN=/usr/bin/maildrop
RM_BIN=/bin/rm
MV_BIN=/bin/mv

# Other variables
MAILDROP_FILTER_HAM="$HTB_TMP_DIR/maildrop.ham"
MAILDROP_FILTER_SPAM="$HTB_TMP_DIR/maildrop.spam"
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
#for BIN in "$SA_LEARN_BIN" "$SPAMC_BIN" "$MAILDROP_BIN" "$RM_BIN" "$MV_BIN"
for BIN in "$SA_LEARN_BIN" "$SPAMC_BIN" "$RM_BIN" "$MV_BIN"
do
  which "$BIN" >/dev/null 2>&1
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 6 "$BIN could not be found"
  fi
done

# Setup temporary directory and files within
if test -d "$HTB_TMP_DIR"; then
  HTB_CLEANUP_AND_EXIT 7 "Temporary directory $HTB_TMP_DIR already exists"
fi
mkdir -p "$HTB_TMP_DIR"
if test $? -ne 0; then
  HTB_CLEANUP_AND_EXIT 7 "Could not create temporary directory $HTB_TMP_DIR"
fi
echo "to \"\$HOME/$MAIL_DIR/$TRAINED_AS_HAM_DIR\"" >$MAILDROP_FILTER_HAM
echo "to \"\$HOME/$MAIL_DIR/$TRAINED_AS_SPAM_DIR\"" >$MAILDROP_FILTER_SPAM

# Create lock file. From now on, do not return without removing the file
echo $$ >"$LOCK_FILE"

# Process all messages
for MESSAGE_TYPE in ham spam
do
  if test "$MESSAGE_TYPE" = "ham"; then
    SRC_BASE_DIR="$HOME/$MAIL_DIR/$TRAINING_HAM_DIR"
    DST_BASE_DIR="$HOME/$MAIL_DIR/$TRAINED_AS_HAM_DIR"
    MAILDROP_FILTER="$MAILDROP_FILTER_HAM"
  elif test "$MESSAGE_TYPE" = "spam"; then
    SRC_BASE_DIR="$HOME/$MAIL_DIR/$TRAINING_SPAM_DIR"
    DST_BASE_DIR="$HOME/$MAIL_DIR/$TRAINED_AS_SPAM_DIR"
    MAILDROP_FILTER="$MAILDROP_FILTER_SPAM"
  else
    continue
  fi

  # Learn messages, then move them to different folder
  for SUB_DIR in new cur
  do
    SRC_DIR="$SRC_BASE_DIR/$SUB_DIR"
    DST_DIR="$DST_BASE_DIR/$SUB_DIR"
    if test ! -d "$SRC_DIR"; then
      echo "Source directory not found: $SRC_DIR"
      continue
    fi
    if test ! -d "$DST_DIR"; then
      echo "Destination directory not found: $DST_DIR"
      continue
    fi

    # Learn/re-learn messages
    echo "Learning $MESSAGE_TYPE from $SRC_DIR for $USER" 2>&1 | logger
    $SA_LEARN_BIN "--$MESSAGE_TYPE" "$SRC_DIR" 2>&1 | logger

    # 1) Let spamc re-classify message - the message has been learned as the correct
    #    type, so the re-classification should give the correct result; the purpose
    #    of re-classification is to add the correct mail headers to the message, also
    #    removing any wrong headers from a previous classification
    # 2) Use maildrop to deliver the cleaned-up message to the final mailbox folder
    # 3) Remove the original message
# TODO: Mark the message as read
#    find "$SUB_DIR" -type f -exec bash -c "$SPAMC_BIN <{} | "$MAILDROP_BIN" $MAILDROP_FILTER; $RM_BIN -f {}" \;
#    find "$SRC_DIR" -type f -exec bash -c "$MV_BIN {} $DST_DIR" \;
  done
done


HTB_CLEANUP_AND_EXIT 0
