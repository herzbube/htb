#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-mkbackupcopy.sh
# | Date:           25 Sep 2016
# | Description:    Makes a recursive copy of a source folder for backup
# |                 purposes. The source folder can be located on a local
# |                 filesystem or on a remote machine reachable via SSH.
# |                 The destination folder can be located either on a local
# |                 filesystem, on a Samba filesystem, or on a Mac OS X
# |                 disk image filesystem. The disk image can optionally
# |                 be located on a Samba filesystem. If the destination
# |                 folder already exists, its content is synchronized
# |                 completely with the source folder. Because the
# |                 copy/sync is made using rsync, the amount of data
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
# |                 [-s <samba-spec>]: Specification of a Samba share to
# |                   mount. The specification conforms to the usual syntax
# |                   used by "mount -t smbfs" (see man "mount_smbfs").
# |                 [-d <disk-image-path>]: The path to a disk image to
# |                   mount. If -s is also specified, the path specified
# |                   here must exist on the Samba share after it is
# |                   mounted. The disk image can be anything that can be
# |                   processed by hdiutil.
# |                 [[user@]host:]source: Specification of source folder.
# |                   Specification of remote source folder conforms to
# |                   the usual rsync / SSH syntax.
# |                 destination: Specification of destination folder. If
# |                   -s is specified, the path specified here must exist
# |                   on the Samba share after it is mounted. If -d is
# |                   specified (regardless of whether -s is also specified),
# |                   the path specified here must exist on the disk image
# |                   after it is mounted.
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

  if test -n "$RSYNC_PATTERNS_WERE_SPECIFIED"; then
    rm -f "$RSYNC_PATTERNSFILE_PATH"
  fi

  # Unmount disk image first because if the Samba share was
  # also specified, the disk image resides on the Samba share
  if test -n "$DISKIMAGE_WAS_SPECIFIED"; then
    if test -n "$DISKIMAGE_WAS_MOUNTED"; then
      hdiutil detach "$DISKIMAGE_MOUNTPOINT"
      if test $? -ne 0; then
        echo "$HTB_SCRIPT_NAME: Failed to unmount disk image" >&2
      fi
    fi

    if test -n "$DISKIMAGE_MOUNTPOINT_WAS_CREATED"; then
      rmdir "$DISKIMAGE_MOUNTPOINT"
      if test $? -ne 0; then
        echo "$HTB_SCRIPT_NAME: Failed to remove disk image mount point" >&2
      fi
    fi
  fi

  if test -n "$SMBSHARE_WAS_SPECIFIED"; then
    if test -n "$SMBSHARE_WAS_MOUNTED"; then
      umount "$SMB_MOUNTPOINT"
      if test $? -ne 0; then
        echo "$HTB_SCRIPT_NAME: Failed to unmount Samba share" >&2
      fi
    fi

    if test -n "$SMBSHARE_MOUNTPOINT_WAS_CREATED"; then
      rmdir "$SMB_MOUNTPOINT"
      if test $? -ne 0; then
        echo "$HTB_SCRIPT_NAME: Failed to remove Samba share mount point" >&2
      fi
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
 [-s <samba-spec>]: Specification of a Samba share to
   mount. The specification conforms to the usual syntax
   used by "mount -t smbfs" (see man "mount_smbfs").
 [-d <disk-image-path>]: The path to a disk image to
   mount. If -s is also specified, the path specified
   here must exist on the Samba share after it is
   mounted. The disk image can be anything that can be
   processed by hdiutil.
 [[user@]host:]source: Specification of source folder.
   Specification of remote source folder conforms to
   the usual rsync / SSH syntax.
 destination: Specification of destination folder. If
  -s is specified, the path specified here must exist
  on the Samba share after it is mounted. If -d is
  specified (regardless of whether -s is also specified),
  the path specified here must exist on the disk image
  after it is mounted.

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
HTB_USAGE_LINE="$HTB_SCRIPT_NAME [-h] [-i <pattern>] [-e <pattern>] [-s <samba-spec>] [-d <disk-image-path>] [[user@]host:]source destination"

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
OPTSOK=hi:e:s:d:
SMB_MOUNTPOINT="/tmp/mount-smbshare-$HTB_SCRIPT_NAME"
DISKIMAGE_MOUNTPOINT="/tmp/mount-diskimage-$HTB_SCRIPT_NAME"
RSYNC_PATTERNSFILE_PATH="/tmp/rsync-patterns-$HTB_SCRIPT_NAME"
DATE_FORMAT="+%Y-%m-%d %H:%M:%S"
SEPARATOR_LINE="--------------------------------------------------------------------------------"
unset RSYNC_PATTERNS_WERE_SPECIFIED
unset SMBSHARE_WAS_SPECIFIED SMBSHARE_MOUNTPOINT_WAS_CREATED SMBSHARE_WAS_MOUNTED
unset DISKIMAGE_WAS_SPECIFIED DISKIMAGE_MOUNTPOINT_WAS_CREATED DISKIMAGE_WAS_MOUNTED

# Make sure that the patterns file does not exist so that the argument
# processing code below can safely use >> to output patterns into the file
rm -f "$RSYNC_PATTERNSFILE_PATH"
if test $? -ne 0; then
  HTB_CLEANUP_AND_EXIT 4 "Error deleting rsync patterns file: $RSYNC_PATTERNSFILE_PATH"
fi

if test -z "$HOSTNAME"; then
  HOSTNAME="$(uname -n)"
fi
KEYCHAIN_SCRIPT="$HOME/.keychain/$HOSTNAME-sh"


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
      echo "+ $OPTARG" >>"$RSYNC_PATTERNSFILE_PATH"
      RSYNC_PATTERNS_WERE_SPECIFIED=1
      ;;
    e)
      echo "- $OPTARG" >>"$RSYNC_PATTERNSFILE_PATH"
      RSYNC_PATTERNS_WERE_SPECIFIED=1
      ;;
    s)
      SMBSHARE_SPEC="$OPTARG"
      SMBSHARE_WAS_SPECIFIED=1
      ;;
    d)
      DISKIMAGE_PATH="$OPTARG"
      DISKIMAGE_WAS_SPECIFIED=1
      ;;
    \?)
      HTB_CLEANUP_AND_EXIT 4 "$HTB_USAGE_LINE"
      ;;
  esac
done
shift $(expr $OPTIND - 1)

if test $# -ne 2; then
  HTB_CLEANUP_AND_EXIT 4 "$HTB_USAGE_LINE"
fi

SOURCE_FULL_PATH="$1"

if test -n "$DISKIMAGE_WAS_SPECIFIED"; then
  DESTINATION_FULL_PATH="$DISKIMAGE_MOUNTPOINT/$2"
elif test -n "$SMBSHARE_WAS_SPECIFIED"; then
  DESTINATION_FULL_PATH="$SMB_MOUNTPOINT/$2"
else
  DESTINATION_FULL_PATH="$2"
fi

if test -n "$SMBSHARE_WAS_SPECIFIED"; then
  if test -d "$SMB_MOUNTPOINT"; then
    HTB_CLEANUP_AND_EXIT 4 "Samba share mount point already exists: $SMB_MOUNTPOINT"
  fi
fi

if test -n "$DISKIMAGE_WAS_SPECIFIED"; then
  if test -d "$DISKIMAGE_MOUNTPOINT"; then
    HTB_CLEANUP_AND_EXIT 4 "Disk image mount point already exists: $DISKIMAGE_MOUNTPOINT"
  fi
fi

if test -n "$DISKIMAGE_WAS_SPECIFIED"; then
  if test -n "$SMBSHARE_WAS_SPECIFIED"; then
    DISKIMAGE_FULL_PATH="$SMB_MOUNTPOINT/$DISKIMAGE_PATH"
  else
    DISKIMAGE_FULL_PATH="$DISKIMAGE_PATH"
  fi
fi

# +------------------------------------------------------------------------
# | Main program processing
# +------------------------------------------------------------------------

# Print "begin" message with timestamp
BEGIN_DATE="$(date "$DATE_FORMAT")"
BEGIN_LINE="Begin copy $BEGIN_DATE"
echo "$SEPARATOR_LINE"
echo "$BEGIN_LINE"
echo "$SEPARATOR_LINE"

# Run keychain script file if it exists. With this we setup access to
# ssh-agent so that rsync can perform a passwordless login.
if test -f "$KEYCHAIN_SCRIPT"; then
  echo "Executing keychain script file ..."
  . "$KEYCHAIN_SCRIPT"
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 5 "Error executing keychain script file: $KEYCHAIN_SCRIPT"
  fi
else
  echo "No keychain script file executed"
fi

# Mount Samba share if it was specified
if test -n "$SMBSHARE_WAS_SPECIFIED"; then
  echo "Creating Samba share mount point $SMB_MOUNTPOINT ..."
  mkdir -p "$SMB_MOUNTPOINT"
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 5 "Error creating Samba share mount point"
  fi
  SMBSHARE_MOUNTPOINT_WAS_CREATED=1

  # Don't print Samba share spec, it may contain a password
  echo "Mounting Samba share ..."
  mount -t smbfs "$SMBSHARE_SPEC" "$SMB_MOUNTPOINT"
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 5 "Error mounting Samba share"
  else
    SMBSHARE_WAS_MOUNTED=1
  fi
fi

# Mount disk image if it was specified
if test -n "$DISKIMAGE_WAS_SPECIFIED"; then
  # Can check this only after Samba share was mounted because disk image resides
  # on Samba share
  if test ! -d "$DISKIMAGE_FULL_PATH"; then
    HTB_CLEANUP_AND_EXIT 5 "Disk image does not exist: $DISKIMAGE_FULL_PATH"
  fi

  echo "Creating disk image mount point $DISKIMAGE_MOUNTPOINT ..."
  mkdir -p "$DISKIMAGE_MOUNTPOINT"
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 5 "Error creating disk image mount point"
  fi
  DISKIMAGE_MOUNTPOINT_WAS_CREATED=1

  echo "Mounting disk image $DISKIMAGE_FULL_PATH ..."
  hdiutil attach -mountpoint "$DISKIMAGE_MOUNTPOINT" "$DISKIMAGE_FULL_PATH"
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 5 "Error mounting disk image"
  else
    DISKIMAGE_WAS_MOUNTED=1
  fi
fi

# Create destination folder if it does not exist
if test ! -d "$DESTINATION_FULL_PATH"; then
  echo "Creating destination folder $DESTINATION_FULL_PATH ..."
  mkdir -p "$DESTINATION_FULL_PATH"
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 5 "Error creating destination folder"
  fi
fi

# Perform sync. Notes:
# - The --archive option implies --recursive
# - The --xattrs option is especially important for Mac OS X (the resource
#   fork is stored as an extended attribute, the Finder also stores data
#   in an extended attribute, etc.)
# - We obtain include/exclude patterns from a file, not from command line
#   options (e.g. --exclude=foo) because patterns might contain spaces,
#   and that would require us to perform complicated eval logic for proper
#   double quote handling. We use --exclude-from to specify the patterns
#   file even though it may contain include patterns - rsync can handle
#   that.
echo "Copying data ..."
if test -n "$RSYNC_PATTERNS_WERE_SPECIFIED"; then
  rsync --archive --compress --delete --delete-excluded --xattrs --verbose --exclude-from="$RSYNC_PATTERNSFILE_PATH" "$SOURCE_FULL_PATH" "$DESTINATION_FULL_PATH"
else
  rsync --archive --compress --delete --delete-excluded --xattrs --verbose "$SOURCE_FULL_PATH" "$DESTINATION_FULL_PATH"
fi

if test $? -ne 0; then
  HTB_CLEANUP_AND_EXIT 5 "Error while copying data"
fi

# Print "end" message with timestamp
END_DATE="$(date "$DATE_FORMAT")"
END_LINE="End copy $END_DATE"
echo "$SEPARATOR_LINE"
echo "$END_LINE"
echo "$SEPARATOR_LINE"

# Unmount everything and remove mount points
HTB_CLEANUP_AND_EXIT 0
