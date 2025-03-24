#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-sftp-get.sh
# | Date:           24 Mar 2025
# | Description:    Uses SFTP to transfer files or folders from a remote host.
# |                 Folders are transferred recursively. To support backup
# |                 scenarios where a remote folder contains the same file
# |                 in several versions (e.g. rotated log files with a
# |                 numeric suffix, or database dumps with a date in the
# |                 file name), then this script supports specifying regex
# |                 patterns to identify the distinct parts of the file name
# |                 so that only one file from a file set is transferred (the
# |                 one with the most recent modification timestamp).
# |
# |                 This script is tailored for my private backup solution.
# |                 It has been made somewhat flexible, so that there remains
# |                 a slight chance that someone else could find it useful.
# |
# | Arguments:      -h: Print a short help page
# |                 [-d <distinct-regex>]: Specification of a regular expression
# |                   to extract that part from the names of the remote files
# |                   which can be used to identify distinct sets of files from
# |                   which only the one with the most recent modification
# |                   timestamp should be transferred. If no regex is specified,
# |                   then no such optimization occurs and all files in the
# |                   remote folder are transferred. The regex must be an sed
# |                   extended regex that contains at least one group. If more
# |                   than one group is in the regex, only the first one is
# |                   used. Back references are used to extract the file name
# |                   part matched by the group. For instance, if the files
# |                   foo-2025-03-23.zip, foo-2025-03-24.zip,
# |                   foobar-2025-03-23.zip and foobar-2025-03-24.zip exist,
# |                   then the regex "^([^-]+-).*$" can be used to match the
# |                   distinct parts "foo-" and "foobar-". Note that the
# |                   character "-" must be included in the distinction group,
# |                   to avoid problems with the distinction logic which would
# |                   otherwise occur because "foo" is a substring of "foobar".
# |                   Only the files foo-2025-03-24.zip and bar-2025-03-24.zip
# |                   will be transferred (based on the modification timestamp,
# |                   not the date in the file name!).
# |                 [-l <local-file-name-regex>]: Specification of a regular
# |                   expression to extract parts from the names of the remote
# |                   files to use to form the local file name. If this option
# |                   is not specified, then transferred files are stored
# |                   locally under the same name they have remotely. This
# |                   option is only valid if -d is also specified. The regex
# |                   must be an sed extended regex that contains at least two
# |                   groups. If more than two groups are in the regex, only
# |                   the first two are used. Back references are used to
# |                   extract the file name parts matched by the groups. In
# |                   the example given for the -d option, if the regex
# |                   "^([^-]+).*(.zip)$" were used this would cause the local
# |                   file names to be foo.zip and bar.zip.
# |                 [-f <password-file-path>]: Path to a file that contains
# |                   the password to use for authentication. If neither this
# |                   nor -e is specified, then passwordless authentication
# |                   is assumed. If specified this option is forwarded to
# |                   sshpass.
# |                 [-e <password-envvar-name>]: Name of an environment
# |                   variable that contains the password to use for
# |                   authentication. If neither this nor -f is specified,
# |                   then passwordless authentication is assumed. If specified
# |                   this option is forwarded to sshpass.
# |                 [user@]host:source-path: Specification of remote host and
# |                   remote source path, optionally with the name of the user
# |                   to authenticate as. The specification conforms to the
# |                   SFTP syntax. Read the SFTP man page for details of
# |                   different SFTP behaviour when you specify a file or
# |                   a folder. Specifically, the options -d and -l only work
# |                   as expected if the remote source path is a folder.
# |                 destination-folder-path: Specification of destination
# |                   folder. The folder is created if it does not exist.
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
      echo "$ERROR_MESSAGE" >&2
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
 [-d <distinct-regex>]: Specification of a regular expression
   to extract that part from the names of the remote files
   which can be used to identify distinct sets of files from
   which only the one with the most recent modification
   timestamp should be transferred. If no regex is specified,
   then no such optimization occurs and all files in the
   remote folder are transferred. The regex must be an sed
   extended regex that contains at least one group. If more
   than one group is in the regex, only the first one is
   used. Back references are used to extract the file name
   part matched by the group. For instance, if the files
   foo-2025-03-23.zip, foo-2025-03-24.zip,
   foobar-2025-03-23.zip and foobar-2025-03-24.zip exist,
   then the regex "^([^-]+-).*$" can be used to match the
   distinct parts "foo-" and "foobar-". Note that the
   character "-" must be included in the distinction group,
   to avoid problems with the distinction logic which would
   otherwise occur because "foo" is a substring of "foobar".
   Only the files foo-2025-03-24.zip and bar-2025-03-24.zip
   will be transferred (based on the modification timestamp,
   not the date in the file name!).
 [-l <local-file-name-regex>]: Specification of a regular
   expression to extract parts from the names of the remote
   files to use to form the local file name. If this option
   is not specified, then transferred files are stored
   locally under the same name they have remotely. This
   option is only valid if -d is also specified. The regex
   must be an sed extended regex that contains at least two
   groups. If more than two groups are in the regex, only
   the first two are used. Back references are used to
   extract the file name parts matched by the groups. In
   the example given for the -d option, if the regex
   "^([^-]+).*(.zip)$" were used this would cause the local
   file names to be foo.zip and bar.zip.
 [-f <password-file-path>]: Path to a file that contains
   the password to use for authentication. If neither this
   nor -e is specified, then passwordless authentication
   is assumed. If specified this option is forwarded to
   sshpass.
 [-e <password-envvar-name>]: Name of an environment
   variable that contains the password to use for
   authentication. If neither this nor -f is specified,
   then passwordless authentication is assumed. If specified
   this option is forwarded to sshpass.
 [user@]host:source-path: Specification of remote host and
   remote source path, optionally with the name of the user
   to authenticate as. The specification conforms to the
   SFTP syntax. Read the SFTP man page for details of
   different SFTP behaviour when you specify a file or
   a folder. Specifically, the options -d and -l only work
   as expected if the remote source path is a folder.
 destination-folder-path: Specification of destination
   folder. The folder is created if it does not exist.

Exit codes:
 0: No error
 2: Aborted by signal (e.g. Ctrl+C)
 3: Error during initialisation
 4: Error while checking arguments
 5: Error during main program
EOF
}

# +------------------------------------------------------------------------
# | Executes sftp using the script stored in the file whose path is stored
# | in the global variable BATCH_SCRIPT_FILE. The output of the script is
# | stored in the file whose path is stored in the global variable
# | BATCH_SCRIPT_OUTPUT_FILE.
# +------------------------------------------------------------------------
# | Arguments:
# |  * Error message: This argument is used to invoke HTB_CLEANUP_AND_EXIT
# |    if the execution of sftp results in an error.
# +------------------------------------------------------------------------
# | Return values:
# |  None
# +------------------------------------------------------------------------
# | Global variables used:
# |  * BATCH_SCRIPT_FILE
# |  * BATCH_SCRIPT_OUTPUT_FILE
# |  * Many variables defined in this HTB script
# +------------------------------------------------------------------------
# | Global functions called:
# |  * HTB_CLEANUP_AND_EXIT
# +------------------------------------------------------------------------
# | HTB script invoked:
# |  None
# +------------------------------------------------------------------------
EXECUTE_SFTP()
{
  typeset ERROR_MESSAGE="$1"

  # If SOURCE_PATH_SPECIFICATION refers to a file, or a list of files via wildcard,
  # then sftp ignores the content of BATCH_SCRIPT_FILE and starts transferring the
  # files directly.
  #
  # If SOURCE_PATH_SPECIFICATION refers to a folder, then sftp changes the remote
  # working directory to that folder and executes the commands in BATCH_SCRIPT_FILE.
  # File/folder paths in BATCH_SCRIPT_FILE can (and should) therefore be relative
  # to SOURCE_PATH_SPECIFICATION.
  #
  # If in doubt, read the sftp man page.

  if test -n "$USE_PASSWORDLESS_AUTHENTICATION"; then
    TOOL_INVOKED="sftp"
    sftp -r -b "$BATCH_SCRIPT_FILE" "$SOURCE_PATH_SPECIFICATION" >"$BATCH_SCRIPT_OUTPUT_FILE"
  else
    TOOL_INVOKED="sshpass"
    if test -n "$PASSWORD_FILE_PATH"; then    
      sshpass -f "$PASSWORD_FILE_PATH" sftp -r $SSH_OPTION_DISABLE_BATCH_MODE -b "$BATCH_SCRIPT_FILE" "$SOURCE_PATH_SPECIFICATION" >"$BATCH_SCRIPT_OUTPUT_FILE"
    else
      sshpass -e"$PASSWORD_ENVVAR_NAME" sftp -r $SSH_OPTION_DISABLE_BATCH_MODE -b "$BATCH_SCRIPT_FILE" "$SOURCE_PATH_SPECIFICATION" >"$BATCH_SCRIPT_OUTPUT_FILE"
    fi
  fi

  EXIT_CODE=$?
  if test $EXIT_CODE -ne 0; then
    # Provide the exit code for diagnostics. sshpass has quite specific exit codes
    # which are useful for diagnosing problems.
    echo "$TOOL_INVOKED returned with exit code $EXIT_CODE" >&2

    HTB_CLEANUP_AND_EXIT 5 "$ERROR_MESSAGE"
  fi
}

# +------------------------------------------------------------------------
# | Prepares the list of files to transfer using the documented
# | distinction logic for determining for each set of files the one that
# | has the most recent modification timestamp. The file list is written to
# | the file whose path is stored in the global variable BATCH_SCRIPT_FILE.
# +------------------------------------------------------------------------
# | Arguments:
# |  None
# +------------------------------------------------------------------------
# | Return values:
# |  None
# +------------------------------------------------------------------------
# | Global variables used:
# |  * BATCH_SCRIPT_FILE
# |  * Many variables defined in this HTB script
# +------------------------------------------------------------------------
# | Global functions called:
# |  * HTB_CLEANUP_AND_EXIT
# +------------------------------------------------------------------------
# | HTB script invoked:
# |  None
# +------------------------------------------------------------------------
PREPARE_DISTINCT_FILES_TO_TRANSFER()
{
  # Step 1: Prepare a script that fetches a list of all files to transfer.
  # The list is sorted ascending (-r) in order of last modification time (-t),
  # i.e. most recent files at the bottom Later steps rely on the sorting.
  echo "ls -rt1" >"$BATCH_SCRIPT_FILE"

  # Step 2: Execute script to get a list of ALL files to transfer
  EXECUTE_SFTP "Failed to fetch list of files to transfer"

  # Step 3: Extract the part from the remote file names that identifies distinct
  # file sets. Make sure to filter out the line that starts with "sftp>". The
  # output is a list of pairs
  #   file-name-part-matched-by-group-one/file-name-part-matched-by-group-two
  # A slash ("/") is used as separator because we can be sure that this cannot
  # occur within a file name.
  DISTINCT_NAMES="$(grep -v "^sftp>" "$BATCH_SCRIPT_OUTPUT_FILE" | sed $SED_OPTION_EXTENDED_REGEX -e 's/'$DISTINCT_REGEX'/\1/' | sort | uniq)"

  # Exit early if there are no files to transfer
  if test -z "$DISTINCT_NAMES"; then
    HTB_CLEANUP_AND_EXIT 0 "No files found to transfer"
  fi

  # Step 4: Prepare a script that transfers the most recent file of each
  # distinct file set. Using tail relies on step 1 fetching the files sorted
  # ascending in order of last modification time.
  rm -f "$BATCH_SCRIPT_FILE"
  for DISTINCT_NAME in $DISTINCT_NAMES; do
    FILE_NAME_REMOTE="$(grep -v "^sftp>" "$BATCH_SCRIPT_OUTPUT_FILE" | grep "$DISTINCT_NAME" | tail -1)"
    if test -z "$FILE_NAME_REMOTE"; then
      HTB_CLEANUP_AND_EXIT 5 "Failed to determine remote file for distinct file part $DISTINCT_NAME"
    fi

    if test -n "$LOCAL_FILE_NAME_REGEX"; then
      FILE_NAME_LOCAL="$(echo "$FILE_NAME_REMOTE" | sed $SED_OPTION_EXTENDED_REGEX -e 's/'$LOCAL_FILE_NAME_REGEX'/\1\2/')"
      echo "get $FILE_NAME_REMOTE $FILE_NAME_LOCAL" >>"$BATCH_SCRIPT_FILE"
    else
      echo "get $FILE_NAME_REMOTE" >>"$BATCH_SCRIPT_FILE"
    fi
  done
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
HTB_USAGE_LINE="$HTB_SCRIPT_NAME [-h] [-d <distinct-regex>] [-l <local-file-name-regex>] [-f <password-file-path>] [-e <password-envvar-name>] [user@]host:source-folder-path destination-folder-path"

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
OPTSOK=hd:l:f:e:
BATCH_SCRIPT_FILE="$HTB_TMP_DIR/$HTB_SCRIPT_NAME.batch-script"
BATCH_SCRIPT_OUTPUT_FILE="$HTB_TMP_DIR/$HTB_SCRIPT_NAME.batch-script-output"
REQUIRED_TOOLS="sshpass sftp uname sed grep"
SSH_OPTION_DISABLE_BATCH_MODE="-oBatchMode=no"
DATE_FORMAT="+%Y-%m-%d %H:%M:%S"
SEPARATOR_LINE="--------------------------------------------------------------------------------"
unset DISTINCT_REGEX LOCAL_FILE_NAME_REGEX PASSWORD_FILE_PATH PASSWORD_ENVVAR_NAME

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
    d)
      DISTINCT_REGEX="$OPTARG"
      ;;
    l)
      LOCAL_FILE_NAME_REGEX="$OPTARG"
      ;;
    f)
      PASSWORD_FILE_PATH="$OPTARG"
      ;;
    e)
      PASSWORD_ENVVAR_NAME="$OPTARG"
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

SOURCE_PATH_SPECIFICATION="$1"
DESTINATION_FOLDER_PATH="$2"

if test -n "$LOCAL_FILE_NAME_REGEX" -a -z "$DISTINCT_REGEX"; then
  HTB_CLEANUP_AND_EXIT 4 "$HTB_SCRIPT_NAME: -l can only be specified together with -d"
fi

if test -z "$PASSWORD_FILE_PATH" -a -z "$PASSWORD_ENVVAR_NAME"; then
  USE_PASSWORDLESS_AUTHENTICATION=1
  unset SSH_OPTION_DISABLE_BATCH_MODE
elif test -n "$PASSWORD_FILE_PATH" -a -n "$PASSWORD_ENVVAR_NAME"; then
  HTB_CLEANUP_AND_EXIT 4 "$HTB_SCRIPT_NAME: Password file and envvar are mutually exclusive"
elif test -n "$PASSWORD_FILE_PATH"; then
  case "$PASSWORD_FILE_PATH" in
    /*)
      ;;
    *)
      which realpath >/dev/null
      if test $? -eq 0; then
        PASSWORD_FILE_PATH="$(realpath "$PASSWORD_FILE_PATH")"
      else
        PASSWORD_FILE_PATH="$(pwd)/$PASSWORD_FILE_PATH"
      fi
      ;;
  esac
  if test ! -f "$PASSWORD_FILE_PATH" -o ! -r "$PASSWORD_FILE_PATH"; then
    HTB_CLEANUP_AND_EXIT 4 "$HTB_SCRIPT_NAME: Password file is not a file, or is not readable: $PASSWORD_FILE_PATH"
  fi
elif test -n "$PASSWORD_ENVVAR_NAME"; then
  printenv $PASSWORD_ENVVAR_NAME >/dev/null
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 4 "$HTB_SCRIPT_NAME: Password environment variable is not set: $PASSWORD_ENVVAR_NAME"
  fi
fi

if test -z "$SOURCE_PATH_SPECIFICATION"; then
  HTB_CLEANUP_AND_EXIT 4 "$HTB_SCRIPT_NAME: Source path specification is empty"
fi

if test -z "$DESTINATION_FOLDER_PATH"; then
  HTB_CLEANUP_AND_EXIT 4 "$HTB_SCRIPT_NAME: Destination folder path is empty"
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

echo "Checking for presence of required tools ..."
for REQUIRED_TOOL in $REQUIRED_TOOLS; do
  which "$REQUIRED_TOOL" >/dev/null
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 5 "$HTB_SCRIPT_NAME: Required tool not found: $REQUIRED_TOOL"
  fi
done

# On macOS and other BSD-based systems the system-provided sed requires a special option
# to enable extended regex handling (which allows grouping without using backslashes to
# escape the grouping parantheses). Although undocumented, GNU sed also supports that
# option. On non-BSD-based systems that don't use a GNU sed the status is unclear, so
# we just try it out without the option.
echo "Checking sed compatibility ..."
SED_GNU_TEST="$(sed --version 2>/dev/null | grep -i gnu)"
if test -n "$SED_GNU_TEST"; then
  SED_OPTION_EXTENDED_REGEX="-E"
else
  case $(uname) in
    Darwin|*BSD*)      
      SED_OPTION_EXTENDED_REGEX="-E"
      ;;
    *)
      unset SED_OPTION_EXTENDED_REGEX
      ;;
  esac
fi
SED_BACKREFERENCE_TEST="$(echo "--found--" | sed $SED_OPTION_EXTENDED_REGEX -e 's/.*(found).*/\1/' 2>/dev/null)"
if test $? -ne 0 -o "$SED_BACKREFERENCE_TEST" != "found"; then
    HTB_CLEANUP_AND_EXIT 5 "$HTB_SCRIPT_NAME: sed does not support back references"
fi

# Run keychain script file if it exists. With this we setup access to
# ssh-agent so that sftp can perform a passwordless login.
if test -f "$KEYCHAIN_SCRIPT"; then
  echo "Executing keychain script file ..."
  . "$KEYCHAIN_SCRIPT"
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 5 "Error executing keychain script file: $KEYCHAIN_SCRIPT"
  fi
else
  echo "No keychain script file executed"
fi

# Create destination folder if it does not exist
if test ! -d "$DESTINATION_FOLDER_PATH"; then
  echo "Creating destination folder $DESTINATION_FOLDER_PATH ..."
  mkdir -p "$DESTINATION_FOLDER_PATH"
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 5 "Error creating destination folder"
  fi
fi

cd "$DESTINATION_FOLDER_PATH" >/dev/null
if test $? -ne 0; then
  HTB_CLEANUP_AND_EXIT 5 "Failed to change working directory to $DESTINATION_FOLDER_PATH"
fi

# Create temp folder so we can place our batch script file
mkdir -p "$HTB_TMP_DIR"

echo "Determining list of files to transfer ..."
if test -z "$DISTINCT_REGEX"; then
  echo "get *" >>"$BATCH_SCRIPT_FILE"
else
  PREPARE_DISTINCT_FILES_TO_TRANSFER
fi

echo "Transferring files ..."
EXECUTE_SFTP "Failed to transfer files"

echo "Files transferred successfully"

# Print "end" message with timestamp
END_DATE="$(date "$DATE_FORMAT")"
END_LINE="End copy $END_DATE"
echo "$SEPARATOR_LINE"
echo "$END_LINE"
echo "$SEPARATOR_LINE"

HTB_CLEANUP_AND_EXIT 0

