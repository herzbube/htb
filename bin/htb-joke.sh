#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-joke.sh
# | Date:           01 Jan 2011
# | Description:    Print a randomly selected joke to stdout.
# |
# |                 The format of the file that jokes are read from is this:
# |                 A line that starts with a hash character ("#") marks the
# |                 beginning of a joke. Anything after the hash character is
# |                 treated as the author of the joke. A joke may consist of
# |                 any number of lines and may contain any characters, except,
# |                 of course, a hash character at the beginning of the line.
# |                 To make for nicer formatting, the last line of a joke should
# |                 be an empty line.
# |
# | Arguments:      -h: Print a short help page
# |                 -p <probability>: Probability of printing a joke. The
# |                   default is 0.25. Specify 1 to always get a joke.
# |                 -n: Add a new joke to the joke library file
# |                 [file]: Jokes library file to process
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
 -p <probability>: Probability of printing a joke. The default is 0.25. Specify
   1 to always get a joke.
 -n: Add a new joke to the joke library file
 [file]: Jokes library file to process

Exit codes:
 0: No error
 2: Aborted by signal (e.g. Ctrl+C)
 3: Error during initialisation
 4: Error while checking arguments
 5: Error during main program
EOF
}

# +------------------------------------------------------------------------
# | Print a random joke (or not, depending on probability).
# +------------------------------------------------------------------------
# | Arguments:
# |  None
# +------------------------------------------------------------------------
# | Return values:
# |  * 0: No error
# |  * 1: An error occurred
# +------------------------------------------------------------------------
# | Global variables used:
# |  * JOKE_FILE_PATH
# |  * AWK_FILE_PATH
# +------------------------------------------------------------------------
# | Global functions called:
# |  None
# +------------------------------------------------------------------------
# | HTB script invoked:
# |  None
# +------------------------------------------------------------------------

PRINT_JOKE()
{
  # Count number of jokes
  NR_OF_JOKES=`grep -c "^#" $JOKE_FILE_PATH`

  # Generate awk script
  cat << EOF >"$AWK_FILE_PATH"
BEGIN {
  srand()
  if (rand() > $PROBABILITY) { exit }  # Should joke be printed
  srand()
  for (i = 1; i <= $NR_OF_JOKES; i++) { rand() }
  whichJoke = int(rand() * $NR_OF_JOKES)
  currentJoke = 0
}
{
  if (\$0 ~ /^#/)
  {
    currentJoke++
    if ( currentJoke == whichJoke)
    {
      author = substr(\$0, 3)
      gsub(/^ */, "", author)
      print "\\nJoke of the Day - brought to you by "author":"
    }
    next
  }
  # Skip line if it does not belong to the joke that is supposed to be printed
  if ( currentJoke < whichJoke ) { next }
  # Abort if this line belongs to the joke after the one that was just printed
  if ( currentJoke > whichJoke ) { exit }

  print
}
EOF

  # Print random joke
  awk -f "$AWK_FILE_PATH" "$JOKE_FILE_PATH"
  if test $? -eq 0; then
    return 0
  else
    return 1
  fi
}

# +------------------------------------------------------------------------
# | Add a joke to the jokes library file.
# +------------------------------------------------------------------------
# | Arguments:
# |  None
# +------------------------------------------------------------------------
# | Return values:
# |  * 0: Joke was added
# |  * 1: Joke was not added due to user interaction
# |  * 2: Error occurred
# +------------------------------------------------------------------------
# | Global variables used:
# |  * JOKE_FILE_PATH
# |  * TMP_FILE_PATH
# +------------------------------------------------------------------------
# | Global functions called:
# |  None
# +------------------------------------------------------------------------
# | HTB script invoked:
# |  None
# +------------------------------------------------------------------------

ADD_JOKE()
{
  typeset LINE
  typeset YESNO

  cat << EOF
You may add any number of lines. To stop and throw away what you entered so far,
enter the single word "quit" on a line. To stop and actually add the joke to the
library, enter the single word "save" on a line.

Ready, steady, go...

EOF

  rm -f "$TMP_FILE_PATH"
  read LINE
  while test "$LINE" != "quit" -a "$LINE" != "save"; do
    echo "$LINE" >>"$TMP_FILE_PATH"
    read LINE
  done
  if test "$LINE" = "quit"; then
    return 1
  fi

  less "$TMP_FILE_PATH"
  echo ""
  read -p "Save joke to the library as it appears above (y/n)? "
  read YESNO
  if [ "$YESNO" != "y" ]
  then
    return 1
  fi

  echo "# $LOGNAME" >>"$JOKE_FILE_PATH"
  cat "$TMP_FILE_PATH" >>"$JOKE_FILE_PATH"
  echo "" >>"$JOKE_FILE_PATH"
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
HTB_USAGE_LINE="$HTB_SCRIPT_NAME [-hn] [-p <probability>] [file]"

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
OPTSOK=hnp:
PROBABILITY=0.25
JOKE_FILE_PATH="$HTB_SHARE_DIR/joke.of.the.day"
AWK_FILE_PATH="$HTB_TMP_DIR/$HTB_SCRIPT_NAME.awk"
TMP_FILE_PATH="$HTB_TMP_DIR/$HTB_SCRIPT_NAME.tmp"
unset NEW

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
    n)
      NEW=1
      ;;
    p)
      PROBABILITY="$OPTARG"
      ;;
    \?)
      HTB_CLEANUP_AND_EXIT 4 "$HTB_USAGE_LINE"
      ;;
  esac
done
shift $(expr $OPTIND - 1)

if test $# -gt 1; then
  HTB_CLEANUP_AND_EXIT 4 "$HTB_USAGE_LINE"
fi
if test $# -eq 1; then
   JOKE_FILE_PATH="$1"
fi

if test ! -r "$JOKE_FILE_PATH"; then
  HTB_CLEANUP_AND_EXIT 4 "Joke library file $JOKE_FILE_PATH not found or not readable"
fi

if test -n "$NEW" -a ! -w "$JOKE_FILE_PATH"; then
  HTB_CLEANUP_AND_EXIT 4 "No write permission for joke library file"
fi

if test -z "$PROBABILITY"; then
  HTB_CLEANUP_AND_EXIT 4 "Probability not specified"
fi

# +------------------------------------------------------------------------
# | Main program processing
# +------------------------------------------------------------------------

# Make sure that temporary directory exists for both program modes
mkdir -p "$HTB_TMP_DIR"

# Program mode: Add new joke
if test -n "$NEW"; then
  ADD_JOKE
  RETURN_VALUE=$?
  case $RETURN_VALUE in
    0|1) HTB_CLEANUP_AND_EXIT $RETURN_VALUE ;;
      *) HTB_CLEANUP_AND_EXIT 5 "Error while adding joke" ;;
  esac
fi

# Program mode: Print random joke
PRINT_JOKE
if test $? -ne 0; then
  HTB_CLEANUP_AND_EXIT 5 "Error while printing joke"
fi

HTB_CLEANUP_AND_EXIT 0
