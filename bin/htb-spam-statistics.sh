#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-spam-statistics.sh
# | Date:           04 Jul 2024
# | Description:    Prints spam statistics by counting messages in a set of
# |                 well-known (= hardcoded) Maildir folders located in the
# |                 top-level Maildir folder .Junk-statistics. If the -r
# |                 option is used, performs a rotation of the production
# |                 Maildir folders located in the top-level Maildir folder
# |                 .Junk before counting. Rotation consists of:
# |
# |                 - Check if the .Junk-statistics folder exists
# |                   - No: Create the .Junk-statistics folder.
# |                   - Yes: Abort rotation unless the rotation is forced
# |                     (-f option). If the rotation is forced, then delete
# |                     any well-known Maildir folders that already exist
# |                     below .Junk-statistics.
# |                 - Rename/move well-known Maildir folders below .Junk so
# |                   they are then located below .Junk-statistics.
# |                 - Create a new set of well-known Maildir folders below
# |                   .Junk.
# |
# |                 If the .Junk-statistics folder already exists
# |
# | Arguments:      -h: Print a short help page
# |                 -u <user>: Name of the user on whose Maildirs to operate.
# |                 -d <days>: Number of days elapsed since last spam statistics.
# |                 [-r]: If specified performs a rotation as described above.
# |                 [-f]: If specified forces the rotation as described above.
# |                 [-g <group>]: Name of the group which should own new
# |                               Maildirs when performing rotation or
# |                               initialization. If -r or -i is specified, this
# |                               option must be specified as well.
# |                 [-i]: Initialize by creating an empty set of Maildir
# |                       folders below .Junk. This option can only be used
# |                       instead of counting.
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
 -u <user>: Name of the user on whose Maildirs to operate
 -d <days>: Number of days elapsed since last spam statistics
 [-r]: If specified performs a rotation before counting. Rotation consistss of
       1) Check if the .Junk-statistics folder exists
          - No: Create the .Junk-statistics folder.
          - Yes: Abort rotation unless the rotation is forced (-f option). If
                 the rotation is forced, then delete any well-known Maildir
                 folders that already exist below .Junk-statistics.
       2) Rename/move well-known Maildir folders from .Junk to .Junk-statistics
       3) Create new set of well-known Maildir folders below .Junk
 [-f]: If specified forces the rotation (see description of -r).
 [-g <group>]: Name of the group which should own new Maildirs when performing
               rotation or initialization. If -r or -i is specified, this
               option must be specified as well.
 [-i]: Initialize by creating an empty set of Maildir folders below .Junk.
       This option can only be used instead of counting.

Exit codes:
 0: No error
 2: Aborted by signal (e.g. Ctrl+C)
 3: Error during initialisation
 4: Error while checking arguments
 5: Error during main program
EOF
}

# +------------------------------------------------------------------------
# | Creates a Maildir folder.
# |
# | The Maildir folder has the following structure/attributes (according
# | to [1]):
# | - The Maildir folder has three subfolders: cur, tmp, new
# | - The Maildir folder and its subfolders are owned/group-owned by the
# |   specified user/group and have permissons 700.
# |
# | [1] https://en.wikipedia.org/wiki/Maildir
# +------------------------------------------------------------------------
# | Arguments:
# |  * Path of the Maildir folder to create
# |  * Name of the user that owns the Maildir folder
# |  * Name of the group that owns the Maildir folder
# +------------------------------------------------------------------------
# | Return values:
# |  * 0 on success
# |  * 1 on failure (a partially created Maildir folder remains is not
# |    cleaned up)
# +------------------------------------------------------------------------

CREATE_MAILDIR_FOLDER()
{
  typeset MAILDIR_FOLDER_PATH="$1"
  typeset MAILDIR_OWNER_USER_NAME="$2"
  typeset MAILDIR_OWNER_GROUP_NAME="$2"

  mkdir -p "$MAILDIR_FOLDER_PATH/cur"
  if test $? -ne 0; then
    return 1
  fi

  mkdir -p "$MAILDIR_FOLDER_PATH/tmp"
  if test $? -ne 0; then
    return 1
  fi

  mkdir -p "$MAILDIR_FOLDER_PATH/new"
  if test $? -ne 0; then
    return 1
  fi

  chown -R "$MAILDIR_OWNER_USER_NAME:$MAILDIR_OWNER_GROUP_NAME" "$MAILDIR_FOLDER_PATH"
  if test $? -ne 0; then
    return 1
  fi

  chmod -R 700 "$MAILDIR_FOLDER_PATH"
  if test $? -ne 0; then
    return 1
  fi

  return 0
}

# +------------------------------------------------------------------------
# | Rotates Maildir folders as per description in the main header of this
# | script.
# +------------------------------------------------------------------------
# | Arguments:
# |  None
# +------------------------------------------------------------------------
# | Global variables used:
# |  * MAILDIR_NAME_JUNK
# |  * MAILDIR_NAME_JUNKSTATISTICS
# |  * MAILDIR_OWNER_USER_NAME
# |  * MAILDIR_OWNER_GROUP_NAME
# +------------------------------------------------------------------------
# | Global functions called:
# |  * CREATE_MAILDIR_FOLDER
# |  * HTB_CLEANUP_AND_EXIT
# +------------------------------------------------------------------------
# | Return values:
# |  None
# +------------------------------------------------------------------------

ROTATE_MAILDIR_FOLDERS()
{
  echo "Rotating ..."

  echo "  Removing old statistics folders ..."
  if test ! -d .${MAILDIR_NAME_JUNKSTATISTICS}; then
    echo "    No old statistics folders found"
  else
    for JUNKSTATISTICS_FOLDER in .${MAILDIR_NAME_JUNKSTATISTICS}*; do
      echo "    $JUNKSTATISTICS_FOLDER"
      rm -r "$JUNKSTATISTICS_FOLDER"
      if test $? -ne 0; then
        HTB_CLEANUP_AND_EXIT 4 "Failed to remove $JUNKSTATISTICS_FOLDER"
      fi
    done
  fi

  echo "  Renaming junk folders ..."
  for JUNK_FOLDER in .${MAILDIR_NAME_JUNK}*; do
    JUNKSTATISTICS_FOLDER="$(echo "$JUNK_FOLDER" | sed -e 's/^\.'$MAILDIR_NAME_JUNK'/.'$MAILDIR_NAME_JUNKSTATISTICS'/')"

    echo "    $JUNK_FOLDER => $JUNKSTATISTICS_FOLDER"
    mv "$JUNK_FOLDER" "$JUNKSTATISTICS_FOLDER"
    if test $? -ne 0; then
      HTB_CLEANUP_AND_EXIT 4 "Failed to rename $JUNK_FOLDER to $JUNKSTATISTICS_FOLDER"
    fi

    CREATE_MAILDIR_FOLDER "$JUNK_FOLDER" "$MAILDIR_OWNER_USER_NAME" "$MAILDIR_OWNER_GROUP_NAME"
    if test $? -ne 0; then
      HTB_CLEANUP_AND_EXIT 4 "Failed to create new junk folder"
    fi
  done
}

# +------------------------------------------------------------------------
# | Counts the number of messages in 0-n Maildir folders
# +------------------------------------------------------------------------
# | Arguments:
# |  * <n> paths of the Maildir folder to count
# +------------------------------------------------------------------------
# | Return values:
# |  * 0 on success
# |  * 1 on failure
# +------------------------------------------------------------------------
# | Global variables set:
# |  * MAILDIR_FOLDERS_MESSAGE_COUNT
# +------------------------------------------------------------------------

COUNT_MESSAGES_IN_MAILDIR_FOLDERS()
{
  MAILDIR_FOLDERS_MESSAGE_COUNT=0

  for MAILDIR_FOLDER_PATH in "$@"; do
    for SUBFOLDER_NAME in cur new tmp; do
      SUBFOLDER_PATH="$MAILDIR_FOLDER_PATH/$SUBFOLDER_NAME"
      if test ! -d "$SUBFOLDER_PATH"; then
        return 1
      fi

      SUBFOLDER_COUNT="$(ls "$SUBFOLDER_PATH" | wc -l)"
      if test $? -ne 0; then
        return 1
      fi

      MAILDIR_FOLDERS_MESSAGE_COUNT="$(expr $MAILDIR_FOLDERS_MESSAGE_COUNT + $SUBFOLDER_COUNT)"
      if test $? -ne 0 -a $? -ne 1; then
        return 1
      fi
    done
  done

  return 0
}

# +------------------------------------------------------------------------
# | Prints the spam statistics.
# |
# | Meaning of each folder:
# | - Messages classified as spam by SpamAssassin (score >= 5.0)
# |   - spamtrap.other: Messages for which the "To:" header contains one of
# |     the known "spam trap" addresses.
# |   - spamtrap.ianapen: Messages for which the "To:" or "Envelope-To:"
# |     headers contain the string "iana.pen".
# |   - Incoming: Messages which do not have a specific address in the
# |     "To:" or "Envelope-To:" headers.
# | - Messages classified as ham by SpamAssassin (score < 5.0) although they
# |   matched at least one local SA rule
# |   - spamtrap.other-locally-detected-spam: Messages for which the "To:"
# |     header contains one of the known "spam trap" addresses.
# |   - spamtrap.ianapen-locally-detected-spam: Messages for which the "To:"
# |     or "Envelope-To:" headers contain the string "iana.pen".
# |   - DNSbl-Warning-locally-detected-spam: Messages which do not have a
# |     specific address in the "To:" or "Envelope-To:" headers, but which
# |     were classified as potential spam by two or more DNS black lists.
# |   - Incoming-locally-detected-spam: Messages which do not have a specific
# |     address in the "To:" or "Envelope-To:" headers, and which were not
# |     classified as potential spam by two or more DNS black lists.
# | - Messages classified as ham by SpamAssassin (score < 5.0) and which did
# |   not match at least one local SA rule
# |   - DNSbl-Warning: Messages classified as potential spam by two or more
# |     DNS black lists.
# | - Manually populated folders
# |   - Trained-as-spam: Messages that made into the inbox but were found 
# |     to be spam.
# |   - DNSbl-Warning-legitimate: Messages that were in one of the
# |     DNSbl-Warning folders, but which were found to be legitimate messages
# |     (i.e. ham) after manual inspection.
# |
# | These folders are for temporarily holding messages while training.
# | They are not considered when creating the statistics.
# | - Training-ham
# | - Training-spam
# +------------------------------------------------------------------------
# | Arguments:
# |  None
# +------------------------------------------------------------------------
# | Global variables used:
# |  * MAILDIR_NAME_JUNKSTATISTICS
# |  * NUMBER_OF_DAYS_ELAPSED
# +------------------------------------------------------------------------
# | Global functions called:
# |  * COUNT_MESSAGES_IN_MAILDIR_FOLDERS
# |  * HTB_CLEANUP_AND_EXIT
# +------------------------------------------------------------------------
# | Return values:
# |  None
# +------------------------------------------------------------------------

PRINT_STATISTICS()
{
  # ------------------------------------------------------------
  echo "Number of days elapsed: $NUMBER_OF_DAYS_ELAPSED"

  # ------------------------------------------------------------
  COUNTER_NAME="Spam messages received"
  COUNT_MESSAGES_IN_MAILDIR_FOLDERS ".${MAILDIR_NAME_JUNKSTATISTICS}.DNSbl-Warning" \
                                    ".${MAILDIR_NAME_JUNKSTATISTICS}.DNSbl-Warning-legitimate" \
                                    ".${MAILDIR_NAME_JUNKSTATISTICS}.DNSbl-Warning-locally-detected-spam" \
                                    ".${MAILDIR_NAME_JUNKSTATISTICS}.Incoming" \
                                    ".${MAILDIR_NAME_JUNKSTATISTICS}.Incoming-locally-detected-spam" \
                                    ".${MAILDIR_NAME_JUNKSTATISTICS}.spamtrap.ianapen" \
                                    ".${MAILDIR_NAME_JUNKSTATISTICS}.spamtrap.ianapen-locally-detected-spam" \
                                    ".${MAILDIR_NAME_JUNKSTATISTICS}.spamtrap.other" \
                                    ".${MAILDIR_NAME_JUNKSTATISTICS}.spamtrap.other-locally-detected-spam" \
                                    ".${MAILDIR_NAME_JUNKSTATISTICS}.Trained-as-spam"
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 4 "Failed to count: $COUNTER_NAME"
  fi
  SPAM_MESSAGES_RECEIVED="$MAILDIR_FOLDERS_MESSAGE_COUNT"
  echo "$COUNTER_NAME: $SPAM_MESSAGES_RECEIVED"

  # ------------------------------------------------------------
  COUNTER_NAME="Messages per day"
  MESSAGES_PER_DAY=$(awk 'BEGIN { print '$SPAM_MESSAGES_RECEIVED' / '$NUMBER_OF_DAYS_ELAPSED' }')
  echo "$COUNTER_NAME: $MESSAGES_PER_DAY"

  # ------------------------------------------------------------
  COUNTER_NAME="Correctly classified by SpamAssassin"
  COUNT_MESSAGES_IN_MAILDIR_FOLDERS ".${MAILDIR_NAME_JUNKSTATISTICS}.Incoming" \
                                    ".${MAILDIR_NAME_JUNKSTATISTICS}.spamtrap" \
                                    ".${MAILDIR_NAME_JUNKSTATISTICS}.spamtrap.ianapen" \
                                    ".${MAILDIR_NAME_JUNKSTATISTICS}.spamtrap.other"
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 4 "Failed to count: $COUNTER_NAME"
  fi
  CORRECTLY_CLASSIFIED_BY_SPAMASSASSIN="$MAILDIR_FOLDERS_MESSAGE_COUNT"
  if test "$SPAM_MESSAGES_RECEIVED" -gt 0; then
    PERCENTAGE=$(awk 'BEGIN { print '$CORRECTLY_CLASSIFIED_BY_SPAMASSASSIN' / '$SPAM_MESSAGES_RECEIVED' * 100 }')
  else
    PERCENTAGE=0
  fi
  echo "$COUNTER_NAME: $CORRECTLY_CLASSIFIED_BY_SPAMASSASSIN (${PERCENTAGE}%)"

  # ------------------------------------------------------------
  COUNTER_NAME="False negatives - manually trained"
  COUNT_MESSAGES_IN_MAILDIR_FOLDERS ".${MAILDIR_NAME_JUNKSTATISTICS}.Trained-as-spam"
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 4 "Failed to count: $COUNTER_NAME"
  fi
  FALSE_NEGATIVES_MANUALLY_TRAINED="$MAILDIR_FOLDERS_MESSAGE_COUNT"
  if test "$SPAM_MESSAGES_RECEIVED" -gt 0; then
    PERCENTAGE=$(awk 'BEGIN { print '$FALSE_NEGATIVES_MANUALLY_TRAINED' / '$SPAM_MESSAGES_RECEIVED' * 100 }')
  else
    PERCENTAGE=0
  fi
  echo "$COUNTER_NAME: $FALSE_NEGATIVES_MANUALLY_TRAINED (${PERCENTAGE}%)"

  # ------------------------------------------------------------
  COUNTER_NAME="False negatives - local SA rule matched"
  COUNT_MESSAGES_IN_MAILDIR_FOLDERS ".${MAILDIR_NAME_JUNKSTATISTICS}.Incoming-locally-detected-spam" \
                                    ".${MAILDIR_NAME_JUNKSTATISTICS}.spamtrap.ianapen-locally-detected-spam" \
                                    ".${MAILDIR_NAME_JUNKSTATISTICS}.spamtrap.other-locally-detected-spam"
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 4 "Failed to count: $COUNTER_NAME"
  fi
  FALSE_NEGATIVES_MANUALLY_TRAINED="$MAILDIR_FOLDERS_MESSAGE_COUNT"
  if test "$SPAM_MESSAGES_RECEIVED" -gt 0; then
    PERCENTAGE=$(awk 'BEGIN { print '$FALSE_NEGATIVES_MANUALLY_TRAINED' / '$SPAM_MESSAGES_RECEIVED' * 100 }')
  else
    PERCENTAGE=0
  fi
  echo "$COUNTER_NAME: $FALSE_NEGATIVES_MANUALLY_TRAINED (${PERCENTAGE}%)"

  # ------------------------------------------------------------
  COUNTER_NAME="False negatives - DNS blacklist warning"
  COUNT_MESSAGES_IN_MAILDIR_FOLDERS ".${MAILDIR_NAME_JUNKSTATISTICS}.DNSbl-Warning" \
                                    ".${MAILDIR_NAME_JUNKSTATISTICS}.DNSbl-Warning-locally-detected-spam"
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 4 "Failed to count: $COUNTER_NAME"
  fi
  FALSE_NEGATIVES_DNSBL_WARNING="$MAILDIR_FOLDERS_MESSAGE_COUNT"
  if test "$SPAM_MESSAGES_RECEIVED" -gt 0; then
    PERCENTAGE=$(awk 'BEGIN { print '$FALSE_NEGATIVES_DNSBL_WARNING' / '$SPAM_MESSAGES_RECEIVED' * 100 }')
  else
    PERCENTAGE=0
  fi
  echo "$COUNTER_NAME: $FALSE_NEGATIVES_DNSBL_WARNING (${PERCENTAGE}%)"

  # ------------------------------------------------------------
  COUNTER_NAME="False positives"
  COUNT_MESSAGES_IN_MAILDIR_FOLDERS ".${MAILDIR_NAME_JUNKSTATISTICS}.DNSbl-Warning-legitimate"
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 4 "Failed to count: $COUNTER_NAME"
  fi
  FALSE_POSITIVES="$MAILDIR_FOLDERS_MESSAGE_COUNT"
  echo "$COUNTER_NAME: $FALSE_POSITIVES"
}

# +------------------------------------------------------------------------
# | Creates an initial set of Maildir folders below the specified base
# | Maildir.
# +------------------------------------------------------------------------
# | Arguments:
# |  * Base Maildir path 
# +------------------------------------------------------------------------
# | Return values:
# |  * 0 on success
# |  * 1 on failure
# +------------------------------------------------------------------------

INITIALIZE_MAILDIR_FOLDERS()
{
  typeset MAILDIR_FOLDER_BASE_PATH="$1"

  echo "Initializing ..."

  for MAILDIR_FOLDER_SUFFIX in "" \
                               "DNSbl-Warning" \
                               "DNSbl-Warning-legitimate" \
                               "DNSbl-Warning-locally-detected-spam" \
                               "Incoming" \
                               "Incoming-locally-detected-spam" \
                               "spamtrap" \
                               "spamtrap.ianapen" \
                               "spamtrap.ianapen-locally-detected-spam" \
                               "spamtrap.other" \
                               "spamtrap.other-locally-detected-spam" \
                               "Trained-as-spam" \
                               "Training-ham" \
                               "Training-spam"
  do
    if test -z "$MAILDIR_FOLDER_SUFFIX"; then
      MAILDIR_FOLDER_PATH="${MAILDIR_FOLDER_BASE_PATH}"
    else
      MAILDIR_FOLDER_PATH="${MAILDIR_FOLDER_BASE_PATH}.${MAILDIR_FOLDER_SUFFIX}"
    fi

    echo "  $MAILDIR_FOLDER_PATH"

    CREATE_MAILDIR_FOLDER "$MAILDIR_FOLDER_PATH" "$MAILDIR_OWNER_USER_NAME" "$MAILDIR_OWNER_GROUP_NAME"
    if test $? -ne 0; then
      return 1
    fi
  done

  return 0
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
HTB_USAGE_LINE="$HTB_SCRIPT_NAME (-h | -i -u <user> -g <group> | [-r -g <group> [-f]] -u <user> -d <days>)"

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
MAILDIR_NAME="Maildir"
MAILDIR_NAME_JUNK="Junk"
MAILDIR_NAME_JUNKSTATISTICS="Junk-statistics"

# Remaining variables and resources
OPTSOK=hu:d:rfg:i
unset MAILDIR_OWNER_USER_NAME NUMBER_OF_DAYS_ELAPSED MAILDIR_OWNER_GROUP_NAME ROTATE FORCE_ROTATE INITIALIZE

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
      MAILDIR_OWNER_USER_NAME="$OPTARG"
      ;;
    d)
      NUMBER_OF_DAYS_ELAPSED="$OPTARG"
      ;;
    r)
      ROTATE=1
      ;;
    f)
      FORCE_ROTATE=1
      ;;
    g)
      MAILDIR_OWNER_GROUP_NAME="$OPTARG"
      ;;
    i)
      INITIALIZE=1
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

if test -z "$MAILDIR_OWNER_USER_NAME"; then
  HTB_CLEANUP_AND_EXIT 4 "User not specified"
fi

MAILDIR_PATH="/home/$MAILDIR_OWNER_USER_NAME/$MAILDIR_NAME"
if test ! -d "$MAILDIR_PATH"; then
  HTB_CLEANUP_AND_EXIT 4 "Maildir not found: $MAILDIR_PATH"
fi

MAILDIR_PATH_JUNK="$MAILDIR_PATH/.$MAILDIR_NAME_JUNK"
MAILDIR_PATH_JUNKSTATISTICS="$MAILDIR_PATH/.$MAILDIR_NAME_JUNKSTATISTICS"

if test -n "$INITIALIZE"; then
  if test -z "$MAILDIR_OWNER_GROUP_NAME"; then
    HTB_CLEANUP_AND_EXIT 4 "Group not specified"
  fi

  if test -d "$MAILDIR_PATH_JUNK"; then
    HTB_CLEANUP_AND_EXIT 4 "Junk Maildir already exists: $MAILDIR_PATH_JUNK"
  fi
else
  if test -z "$NUMBER_OF_DAYS_ELAPSED"; then
    HTB_CLEANUP_AND_EXIT 4 "Number of days elapsed not specified"
  fi
  expr "$NUMBER_OF_DAYS_ELAPSED" + 1 >/dev/null 2>&1
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 4 "Number of days elapsed is not numeric: $NUMBER_OF_DAYS_ELAPSED"
  fi

  if test -n "$ROTATE"; then
    if test -z "$MAILDIR_OWNER_GROUP_NAME"; then
      HTB_CLEANUP_AND_EXIT 4 "Group not specified"
    fi

    if test ! -d "$MAILDIR_PATH_JUNK"; then
      HTB_CLEANUP_AND_EXIT 4 "Junk Maildir not found: $MAILDIR_PATH_JUNK"
    fi

    if test -d "$MAILDIR_PATH_JUNKSTATISTICS"; then
      if test -z "$FORCE_ROTATE"; then
        HTB_CLEANUP_AND_EXIT 4 "Junk statistics Maildir already exists - specify -f to force overwrite: $MAILDIR_PATH_JUNKSTATISTICS"
      else
        echo "Junk statistics Maildir already exists - overwriting contents because -f specified: $MAILDIR_PATH_JUNKSTATISTICS"
      fi
    fi
  else
    if test -n "$MAILDIR_OWNER_GROUP_NAME"; then
      HTB_CLEANUP_AND_EXIT 4 "Group specified but not rotating"
    fi
  
    if test ! -d "$MAILDIR_PATH_JUNKSTATISTICS"; then
      HTB_CLEANUP_AND_EXIT 4 "Junk statistics Maildir not found: $MAILDIR_PATH_JUNKSTATISTICS"
    fi
  fi
fi

# +------------------------------------------------------------------------
# | Main program processing
# +------------------------------------------------------------------------

cd "$MAILDIR_PATH"

if test -n "$INITIALIZE"; then
  INITIALIZE_MAILDIR_FOLDERS "$MAILDIR_PATH_JUNK"
  if test $? -eq 0; then
    HTB_CLEANUP_AND_EXIT 0
  else
    HTB_CLEANUP_AND_EXIT 4 "Initialization failed"
  fi
else
  if test -n "$ROTATE"; then
    ROTATE_MAILDIR_FOLDERS
  fi
  
  PRINT_STATISTICS

  HTB_CLEANUP_AND_EXIT 0
fi


