#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-cfparse.sh
# | Date:           01 Jan 2011
# | Description:    Processes .ini style configuration files.
# |
# | Arguments:      -h: Print a short help page
# |                 -g <sections>: Global sections (e.g. "global1|global2"). The
# |                   default is "all|global". The intent is two-fold: 1) If an
# |                   .ini file contains a section "[global]", that section will
# |                   match and its content will be printed. 2) If a target
# |                   section "all" is specified, every section in the .ini file
# |                   will match, and the content of all sections will be
# |                   printed.
# |                 -t <sections>: Target section (e.g. "title1|title2")
# |                 -a: Print all sections. -a and -t are mutually exclusive.
# |                   Specifying -a is equivalent to "-t all".
# |                 [file...]: Specification of file(s) to process
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
 -g <sections>: Global sections (e.g. "global1|global2"). The default is
   "all|global". The intent is two-fold: 1) If an .ini file contains a section
   "[global]", that section will match and its content will be printed. 2) If
   a target section "all" is specified, every section in the .ini file will
   match, and the content of all sections will be printed.
 -t <sections>: Target section (e.g. "title1|title2")
 -a: Print all sections. -a and -t are mutually exclusive. Specifying -a is
   equivalent to "-t all"
 [file...]: Specification of file(s) to process

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
HTB_USAGE_LINE="$HTB_SCRIPT_NAME [-ha] [-g <sections>] [-t <sections>] file..."

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
OPTSOK=hag:t:
AWK_FILE_PATH="$HTB_TMP_DIR/$HTB_SCRIPT_NAME.awk"
unset ALL GLOBAL_SECTIONS TARGET_SECTIONS

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
    a)
      ALL=1
      ;;
    g)
      GLOBAL_SECTIONS="$OPTARG"
      ;;
    t)
      TARGET_SECTIONS="$OPTARG"
      ;;
    \?)
      HTB_CLEANUP_AND_EXIT 4 "$HTB_USAGE_LINE"
      ;;
  esac
done
shift $(expr $OPTIND - 1)

if test $# -eq 0; then
  HTB_CLEANUP_AND_EXIT 4 "No files specified"
fi

for FILE in "$@"; do
  if test ! -r "$FILE"; then
    HTB_CLEANUP_AND_EXIT 4 "File $FILE does not exist or is not readable"
  fi
done

if test -z "$GLOBAL_SECTIONS"; then
  GLOBAL_SECTIONS="global|all"
fi

if test -n "$ALL"; then
  if test -n "$TARGET_SECTIONS"; then
    HTB_CLEANUP_AND_EXIT 4 "-a and -t are mutually exclusive"
   fi
   TARGET_SECTIONS="$GLOBAL_SECTIONS"
fi

if test -z "$TARGET_SECTIONS"; then
  HTB_CLEANUP_AND_EXIT 4 "No target section specified"
fi

# +------------------------------------------------------------------------
# | Generate awk script
# +------------------------------------------------------------------------

mkdir -p "$HTB_TMP_DIR"
cat << EOF >"$AWK_FILE_PATH"
# This script processes one .ini style configuration file. The file is
# processed according to the following rules:
#  * Everything after a hash character ("#") up to the end of line is treated
#    as a comment and is removed from the output
#  * Whitespace at the beginning and end of line is removed
#  * Whitespace around the first "=" character in a line is removed
#  * Empty lines are ignored
#  * A section header must be alone on a line. The header starts a new section.
#  * All lines before the first section header are ignored (even if they are
#    not empty lines)
#  * A section header consists of one or more section titles that are enclosed
#    by brackets ("[]"). Section titles must be separated by a pipe character
#    ("|"). Example (without quotes): "[title1|title2]"
#  * Section titles must not contain meta characters that have a meaning in
#    regular expresssions. If in doubt, use lowercase or uppercase alphabet
#    characters, digits, and the underscore character ("_").
#    WARNING: There are no checks for illegal characters. If meta characters
#    are used the result is undefined.
#  * Case is important!
#  * A section title does *NOT* need to be unique, it may appear multiple times
#
# Whenever this script encounters a section header, it compares the titles of
# this header to the specified target sections. If there is at least one match,
# all lines up to the following section header are printed to stdout.
#
# This script also considers global titles. If 

# Return values:
#  * 0: No error
#  * 1: Error

BEGIN {
  # Initialisation
  exitValue = 0
  whiteSpaceMatch = "[ \\t]+"
  validSectionFlag = 0
  globalSectionFlag = 0
  foundFirstSection = 0

  # Arguments from shell script
  globalSections = "$GLOBAL_SECTIONS"
  targetSections = "$TARGET_SECTIONS"

  # A few basic argument checks
  if (length(globalSections) == 0) { exitValue = 1; exit exitValue }
  if (length(targetSections) == 0) { exitValue = 1; exit exitValue }

  # Construct regular expression for matching global sections
  globalSectionMatch = "^("globalSections")\$"

  # Is one of the target sections a global section? If so, all sections can
  # be printed
  nrOfTargetSections = split(targetSections, targetSectionList, "|")
  for (i = 1; i <= nrOfTargetSections; i++)
  {
    if (targetSectionList[i] ~ globalSectionMatch)
    {
      globalSectionFlag = 1
      break      # no need to test more sections
    }
  }
}
{
  cleanupLine()
  if ( length(\$0) == 0 ) { next }

  # If current line is a section header: Check whether it matches one of the
  # requested sections
  if (\$0 ~ /^\\[.*]\$/ )
  {
    foundFirstSection = 1
    if (globalSectionFlag == 0)
    {
      validSectionFlag = checkForValidSection(\$0)
    }
    next
  }

  # Ignore all lines before the first section
  if (! foundFirstSection) { next }

  # Print to stdout if the current section matches, or all sections must be
  # printed
  if ( validSectionFlag || globalSectionFlag ) { print }
}
END {
  # exit statements in the BEGIN or the main processing section jumps to this
  # end section -> we have to repeat the exit statement here
  exit exitValue
}

# +------------------------------------------------------------------------
# | Cleans the current line ($0) from all comments, whitespace and other
# | unneded stuff. If nothing remains the empty line will be skipped
# | later on in the main program.
# +------------------------------------------------------------------------
# | Arguments:
# |  None
# +------------------------------------------------------------------------
# | Return values:
# |  None
# +------------------------------------------------------------------------
function cleanupLine()
{
  # Remove comments
  gsub("#.*\$", "", \$0)

  # Remove whitespace from the beginning of line
  gsub("^"whiteSpaceMatch, "", \$0)

  # Remove whitespace from the end of line
  gsub(whiteSpaceMatch"\$", "", \$0)

  # Remove whitespace before and after the first "=" character of a line.
  # A more elegant solution would be nice, but back-references do not work
  # in awk :-(
  i = split(\$0, z, "=")
  if (i >= 2)
  {
    gsub(whiteSpaceMatch"\$", "", z[1])
    gsub("^"whiteSpaceMatch, "", z[2])
    \$0 = ""
    for (j = 1; j <= i; j++) { \$0 = \$0"="z[j] }
    \$0 = substr(\$0, 2 )
  }
}

# +------------------------------------------------------------------------
# | Check if the specified section header matches one of the target
# | sections or one of the global sections.
# |
# | The section header must be enclosed by brackets ("[]"). If the header
# | consists of multiple titles, those titles must be separated by a pipe
# | character ("|").
# |
# | Example (without quotes): "[title1|title2]"
# +------------------------------------------------------------------------
# | Arguments:
# |  * Section header
# +------------------------------------------------------------------------
# | Return values:
# |  * 0: Section invalid
# |  * 1: Section valid
# +------------------------------------------------------------------------
function checkForValidSection(sectionHeader)
{
  # Default: Section ist invalid
  returnValue = 0

  # Remove section header delimiters "[]"
  gsub(/[[\\]]/, "", sectionHeader)

  # Section titles must be separated by "|"
  nrOfSections = split(sectionHeader, sectionList, "|")

  # Examine each section title
  for (i = 1; i <= nrOfSections; i++)
  {
    # Check if there is a match with at least one target section
    for (j = 1; j <= nrOfTargetSections; j++)
    {
      # The section matches if its name is equal to one of the target sections,
      # or one of the global sections
      if ( sectionList[i] == targetSectionList[j] || sectionList[i] ~ globalSectionMatch)
      {
        # awk does not have a statement that could be used to bail out of two
        # loops :-( If it had we could stop here.
        returnValue = 1
       }
    }
  }
  return returnValue
}
EOF

# +------------------------------------------------------------------------
# | Main program processing
# +------------------------------------------------------------------------

for FILE in "$@"; do
  awk -f "$AWK_FILE_PATH" "$FILE"
  if test $? -ne 0; then
    HTB_CLEANUP_AND_EXIT 5 "Error while processing $FILE"
  fi
done

HTB_CLEANUP_AND_EXIT 0
