#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-mkbackupcopy.sh
# | Date:           25 Sep 2016
# | Description:    Makes a recursive copy of a source folder for backup
# |                 purposes. The source folder can be located on a local
# |                 filesystem or on a remote machine. The destination
# |                 folder is always located on a local filesystem. If the
# |                 destination folder already exists, its content is
# |                 synchronized completely with the source folder. Because
# |                 the copy/sync is made using rsync, the amount of data
# |                 transferred between source and destination is minimal.
# |                 By using exclude/include patterns it is possible to
# |                 restrict the copy/sync operation to certain files and
# |                 subfolders only.
# |
# |                 This script is tailored for my private backup solution.
# |                 It has been made somewhat flexible, so that there remains
# |                 a slight chance that someone else could find it useful.
# |
# | Arguments:      -h: Print a short help page
# |                 -i <pattern>: An include pattern to be passed to rsync.
# |                   This parameter can be specified multiple times. The
# |                   order in which include/exclude patterns are specified
# |                   is important.
# |                 -e <pattern>: An exclude pattern to be passed to rsync.
# |                   This parameter can be specified multiple times. The
# |                   order in which include/exclude patterns are specified
# |                   is important.
# |                 [[user@]host:]source: Specification of source folder.
# |                   Specification of remote source folder conforms to
# |                   the usual rsync / SSH syntax.
# |                 destination: Specification of destination folder.
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
 -i <pattern>: An include pattern to be passed to rsync.
   This parameter can be specified multiple times. The
   order in which include/exclude patterns are specified
   is important.
 -e <pattern>: An exclude pattern to be passed to rsync.
   This parameter can be specified multiple times. The
   order in which include/exclude patterns are specified
   is important.
 [[user@]host:]source: Specification of source folder.
   Specification of remote source folder conforms to
   the usual rsync / SSH syntax.
 destination: Specification of destination folder.

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
HTB_USAGE_LINE="$HTB_SCRIPT_NAME [-h] [-i <pattern>] [-e <pattern>] [[user@]host:]source destination"

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
OPTSOK=hi:e:
DATE_FORMAT="+%Y-%m-%d %H:%M:%S"
SEPARATOR_LINE="--------------------------------------------------------------------------------"
unset PATTERNS

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
    i)
      PATTERNS="$PATTERNS --include=$OPTARG"
      ;;
    e)
      PATTERNS="$PATTERNS --exclude=$OPTARG"
      ;;
    \?)
      HTB_CLEANUP_AND_EXIT 4 "$HTB_USAGE_LINE"
      ;;
  esac
done
shift $(expr $OPTIND - 1)
FILES="$*"

if test $# -ne 2; then
  HTB_CLEANUP_AND_EXIT 4 "$HTB_USAGE_LINE"
fi

SOURCE="$1"
DESTINATION="$2"

# +------------------------------------------------------------------------
# | Main program processing
# +------------------------------------------------------------------------

# Print "begin" message with timestamp
BEGIN_DATE="$(date "$DATE_FORMAT")"
BEGIN_LINE="Begin copy $BEGIN_DATE"
echo "$SEPARATOR_LINE"
echo "$BEGIN_LINE"
echo "$SEPARATOR_LINE"

# Run keychain script file - with this we setup access to ssh-agent
# so that rsync can perform a passwordless login
[ -z "$HOSTNAME" ] && HOSTNAME=`uname -n`
KEYCHAIN_SCRIPT="$HOME/.keychain/$HOSTNAME-sh"
if test ! -f "$KEYCHAIN_SCRIPT"; then
  HTB_CLEANUP_AND_EXIT 5 "keychain script file does not exist: $KEYCHAIN_SCRIPT"
fi
echo "Executing keychain script file ..."
. "$KEYCHAIN_SCRIPT"
if test $? -ne 0; then
  HTB_CLEANUP_AND_EXIT 5 "Error executing keychain script file: $KEYCHAIN_SCRIPT"
fi

# Create local backups folder if it does not exist
if test ! -d "$DESTINATION"; then
  echo "Creating local destination folder $DESTINATION ..."
  mkdir -p "$DESTINATION"
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 5 "Failed to create local destination folder"
  fi
fi

# Run the sync
echo "Copying data ..."
# --archive implies --recursive
rsync --archive --compress --delete-excluded --verbose $PATTERNS "$SOURCE" "$DESTINATION"
if test $? -ne 0; then
  HTB_CLEANUP_AND_EXIT 5 "Error while copying data"
fi

# Print "end" message with timestamp
END_DATE="$(date "$DATE_FORMAT")"
END_LINE="End copy $END_DATE"
echo "$SEPARATOR_LINE"
echo "$END_LINE"
echo "$SEPARATOR_LINE"


HTB_CLEANUP_AND_EXIT 0
