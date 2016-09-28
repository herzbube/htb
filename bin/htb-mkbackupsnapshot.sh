#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-mkbackupsnapshot.sh
# | Date:           25 Sep 2016
# | Description:    Creates a snapshot of a folder for backup purposes.
# |                 The snapshot is made using bup. The bup repository
# |                 as well as the folder to snapshot must be located on
# |                 a local filesystem.
# |
# |                 This script is tailored for my private backup solution.
# |                 It has been made somewhat flexible, so that there remains
# |                 a slight chance that someone else could find it useful.
# |
# | Arguments:      -h: Print a short help page
# |                 source: Specification of folder to snapshot.
# |                 bup-repository: Specification of the bup repository
# |                   folder.
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
 source: Specification of folder to snapshot.
 bup-repository: Specification of the bup repository
   folder.

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
HTB_USAGE_LINE="$HTB_SCRIPT_NAME [-h] source bup-repository"

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
DATE_FORMAT="+%Y-%m-%d %H:%M:%S"
DATE_FORMAT_SNAPSHOT_NAME="+%Y-%m-%d-%H-%M-%S"
DATE_SNAPSHOT_NAME="$(date "$DATE_FORMAT_SNAPSHOT_NAME")"
DATE_FORMAT_DISK_USAGE="+%Y-%m-%d %H:%M:%S"
DATE_DISK_USAGE="$(date "$DATE_FORMAT_DISK_USAGE")"
SEPARATOR_LINE="--------------------------------------------------------------------------------"


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
FILES="$*"

if test $# -ne 2; then
  HTB_CLEANUP_AND_EXIT 4 "$HTB_USAGE_LINE"
fi

SOURCE="$1"
BUP_REPOSITORY="$2"
# BUP_DIR is recognized by bup
export BUP_DIR="$BUP_REPOSITORY"

# +------------------------------------------------------------------------
# | Main program processing
# +------------------------------------------------------------------------

# Print "begin" message with timestamp
BEGIN_DATE="$(date "$DATE_FORMAT")"
BEGIN_LINE="Begin snapshot $BEGIN_DATE"
echo "$SEPARATOR_LINE"
echo "$BEGIN_LINE"
echo "$SEPARATOR_LINE"

if test ! -d "$SOURCE"; then
  HTB_CLEANUP_AND_EXIT 5 "Source folder does not exist: $SOURCE"
fi

if test ! -d "$BUP_REPOSITORY"; then
  echo "Creating bup repository $BUP_REPOSITORY ... "
  bup init
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 5 "Error creating bug repository"
  fi
fi

echo "Updating index of source folder $SOURCE ... "
bup index "$SOURCE"
if test $? -ne 0; then
  HTB_CLEANUP_AND_EXIT 5 "Error updating index of source folder"
fi

echo "Creating snapshot ... "
SNAPSHOT_NAME="backup-$DATE_SNAPSHOT_NAME"
bup save -n "$SNAPSHOT_NAME" "$SOURCE"
if test $? -ne 0; then
  HTB_CLEANUP_AND_EXIT 5 "Error creating snapshot"
fi

echo "Writing parity information ... "
bup fsck -g
if test $? -ne 0; then
  HTB_CLEANUP_AND_EXIT 5 "Error writing parity information"
fi

echo "Calculating disk usage ... "
DISK_USAGE="$(du -sk "$SOURCE" | cut -f1)"
if test $? -ne 0; then
  HTB_CLEANUP_AND_EXIT 5 "Error calculating disk usage for $SOURCE"
fi
echo "Disk usage source folder: $DATE_DISK_USAGE $DISK_USAGE"
DISK_USAGE="$(du -sk "$BUP_REPOSITORY" | cut -f1)"
if test $? -ne 0; then
  HTB_CLEANUP_AND_EXIT 5 "Error calculating disk usage for $BUP_REPOSITORY"
fi
echo "Disk usage bup repository: $DATE_DISK_USAGE $DISK_USAGE"


# Print "end" message with timestamp
END_DATE="$(date "$DATE_FORMAT")"
END_LINE="End snapshot $END_DATE"
echo "$SEPARATOR_LINE"
echo "$END_LINE"
echo "$SEPARATOR_LINE"


HTB_CLEANUP_AND_EXIT 0
