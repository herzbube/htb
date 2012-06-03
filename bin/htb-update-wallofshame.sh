#!/bin/bash

# ------------------------------------------------------------
# This script generates a HTML file with IP addresses that have
# recently offended the network security rules on this system.
#
# The HTML file is intended for publication on the Internet.
# It contains one or more tables with IP addresses, each table
# listing those addresses that have offended a specific rule.
# Most recent offenders appear first.
#
# The HTML file makes use of server side includes (must be
# enabled by the web server) to embed an external HTML snippet
# from a manually maintained file.
#
# This script examines the current /var/log/syslog and all
# available older versions of that log (/var/log/syslog.[0-9]+).
# ------------------------------------------------------------

MYNAME="$(basename $0)"
TMP_DIR="/tmp/$MYNAME.$$"
LOG_DIR="/var/log"
LOG_FILE="syslog"
LOG_PATH="$LOG_DIR/$LOG_FILE"
AWK_FILE="$TMP_DIR/$MYNAME.awk"
HTML_FILE="wall-of-shame.shtml"
MANUAL_HTML_FILE="manual-$HTML_FILE"
HTML_PUBLISHED_DIR="/var/www/pelargir.herzbube.ch"
SYSTEM_NAME_TO_PRINT="$(hostname --fqdn)"
GENERATED_DATE_TO_PRINT="$(date +'%d.%m.%Y-%H:%M:%S')"

# ------------------------------------------------------------
# Temporary directory handling
if test -d "$TMP_DIR"; then
  rm -rf "$TMP_DIR"
  if test $? -ne 0; then
    echo "$MYNAME: Could not remove temporary directory $TMP_DIR"
    exit 1
  fi
fi
mkdir -p "$TMP_DIR"
if test $? -ne 0; then
  echo "$MYNAME: Could not create temporary directory $TMP_DIR"
  exit 1
fi

# ------------------------------------------------------------
# Prepare single log file from the current log file and all
# available older log files
if test -f "$LOG_PATH"; then
  cp "$LOG_PATH" "$TMP_DIR/$LOG_FILE"
  if test $? -ne 0; then
    echo "$MYNAME: Could not copy $LOG_PATH to $TMP_DIR/$LOG_FILE"
    rm -rf "$TMP_DIR"
    exit 1
  fi
fi
# Using "ls -t" makes sure that the most recent files
# are processed first
for OLD_LOG_FILE in $(ls -t ${LOG_PATH}.[0-9]*)
do
  case "$OLD_LOG_FILE" in
    *.gz)
      zcat "$OLD_LOG_FILE" >>"$TMP_DIR/$LOG_FILE"
      ;;
    *)
      cat "$OLD_LOG_FILE" >>"$TMP_DIR/$LOG_FILE"
      ;;
  esac
done

# ------------------------------------------------------------
# Create temporary awk script
cat >"$AWK_FILE" << EOF
BEGIN {
  SSH_BRUTE_FORCE="SSH_brute_force"
  FTP_LOGIN_REFUSED="FTP LOGIN REFUSED"
  tableOrderCount = 0
  arrayTableOrder[tableOrderCount++] = SSH_BRUTE_FORCE
  arrayTableOrder[tableOrderCount++] = FTP_LOGIN_REFUSED
}
{
  # Collect entries for the "SSH brute force" table
  if (\$0 ~ SSH_BRUTE_FORCE)
  {
    eventDate = getTime(\$0)
    srcIP = \$0
    gsub(/^.*SRC=/, "", srcIP)
    gsub(/ .*\$/, "", srcIP)
    arrayEventCount[SSH_BRUTE_FORCE, srcIP]++
    arrayEventDate[SSH_BRUTE_FORCE, srcIP] = eventDate
  }
  else if (\$0 ~ FTP_LOGIN_REFUSED)
  {
    eventDate = getTime(\$0)
    srcIP = \$0
    gsub(/^.*FROM [^ ]+ \[/, "", srcIP)
    gsub(/\].*\$/, "", srcIP)
    arrayEventCount[FTP_LOGIN_REFUSED, srcIP]++
    arrayEventDate[FTP_LOGIN_REFUSED, srcIP] = eventDate
  }
}
END {
  # Collect events in arrayTableLines
  for (indexEvent in arrayEventCount)
  {
    split(indexEvent, indexes, SUBSEP)
    tableName = indexes[1]
    srcIP = indexes[2]
    eventCount = arrayEventCount[indexEvent]
    eventDate = arrayEventDate[indexEvent]

    # Initialize table line count when the table is encountered for the first time
    if (length(arrayTableLineCount[tableName]) == 0)
      arrayTableLineCount[tableName] = 0
    # Construct a single table line
    arrayTableLines[tableName, arrayTableLineCount[tableName]++] = "<tr><td>" srcIP "</td><td>" eventCount "</td><td>" eventDate "</td></tr>"
  }

  # Print out document start
  print "<html>"
  print "<head><title>Wall Of Shame</title></head>"
  print "<body>"
  print "<h1>Content</h1>"
  print "<p>"
  print "This is another <a href=\"http://en.wikipedia.org/wiki/Wall_of_shame_(epithet)\">Wall Of Shame</a> document. It contains lists of IP"
  print "addresses that have recently offended the network security rules on my Internet gateway <tt>$SYSTEM_NAME_TO_PRINT</tt>."
  print "IP addresses listed here may be temporarily or permanently blocked from accessing certain services. If your IP address is listed here and you"
  print "feel it is in error, please contact me at <a href=\"mailto:herzbube@herzbube.ch\">herzbube@herzbube.ch</a>."
  print "</p>"
  print "<h1>Structure</h1>"
  print "<p>"
  print "This document contains various lists, each of which contains addresses that have offended a specific rule in the recent past. For every IP"
  print "address the list contains the number of offences and the date of the most recent offence."
  print "</p>"
  print "<h1>Status</h1>"
  print "<p>This document is automatically updated on a regular basis. The last update happened on $GENERATED_DATE_TO_PRINT</p>"
  print "<h1>The lists</h1>"

  # Print out events, table by table, in the table order defined in the BEGIN
  # section of this script
  atLeastOneTableWasPrinted = 0
  for (tableOrderIndex = 0; tableOrderIndex < tableOrderCount; tableOrderIndex++)
  {
    tableName = arrayTableOrder[tableOrderIndex]
    # Suppress table if there are no events for it
    if (length(arrayTableLineCount[tableName]) == 0)
      continue
    # Print a ruler that separates tables (only from the 2nd table onwards)
    if (atLeastOneTableWasPrinted == 0)
      atLeastOneTableWasPrinted = 1
    tableLineCount = arrayTableLineCount[tableName]
    print "<h2>" getTableHeading(tableName) "</h2>"
    print "<p>" getTableDescription(tableName) "</p>"
    print "<table border=\"1\" cellpadding=\"5\">"
    print "<tr><th>Offending IP address</th><th>Number of offences</th><th>Date of most recent offence</th></tr>"
    for (tableLineIndex = 0; tableLineIndex < tableLineCount; tableLineIndex++)
      print arrayTableLines[tableName, tableLineIndex]
    print "</table>"
  }

  # Special handling for manual entries
  print "<!--#include virtual=\"$MANUAL_HTML_FILE\"-->"

  # Print out document end
  print "</body>"
  print "</html>"
}

# Examine a single line from the syslog and return a string
# that contains the date when the event occurred
function getTime(line)
{
  gsub(/ pelargir.*\$/, "", line)
  return line
}

# Returns a user-visible heading text for tableName.
# The text will be marked up in <h1> or some similar manner.
function getTableHeading(tableName)
{
  if (tableName == SSH_BRUTE_FORCE)
    heading = "SSH brute force attacks"
  else if (tableName == FTP_LOGIN_REFUSED)
    heading = "FTP login refused"
  else
    heading = "Unknown table name " tableName

  return heading
}

# Returns a user-visible description text for tableName.
# The text will be marked up in <p> or some similar manner.
function getTableDescription(tableName)
{
  if (tableName == SSH_BRUTE_FORCE)
  {
    desc = "This table lists IP addresses that have attempted more than 5 TCP connections to port 22 (the SSH port) within a time frame of 20 seconds."
    desc = desc " In my opinion, the only reason why someone would behave like this is because he or she wants to try some sort of brute force attack"
    desc = desc " on the SSH service, possibly a dictionary attack. IP addresses that behave in this way are blocked on the SSH port until they"
    desc = desc " completely cease all activities on the SSH port for 20 seconds."
  }
  else if (tableName == FTP_LOGIN_REFUSED)
  {
    desc = "This table lists IP addresses that have attempted an FTP login, but failed. So far I have not taken any automated measures against these"
    desc = desc " offenders, although if caught red-handed at repeated login attempts I will personally put someone's IP on a black list for some time."
  }
  else
    desc = "Unknown table name " tableName

  return desc
}
EOF

# ------------------------------------------------------------
# Process log file with awk script
awk -f "$AWK_FILE" <"$TMP_DIR/$LOG_FILE" >"$TMP_DIR/$HTML_FILE"
if test $? -ne 0; then
  echo "$MYNAME: Error executing awk script $AWK_FILE"
  rm -rf "$TMP_DIR"
  exit 1
fi

# ------------------------------------------------------------
# Overwrite published HTML file
cp "$TMP_DIR/$HTML_FILE" "$HTML_PUBLISHED_DIR/$HTML_FILE"
if test $? -ne 0; then
  echo "$MYNAME: Error overwriting published HTML file $HTML_PUBLISHED_DIR/$HTML_FILE with generated HTML file $TMP_DIR/$HTML_FILE"
  rm -rf "$TMP_DIR"
  exit 1
fi

# ------------------------------------------------------------
# Remove temporary files
rm -rf "$TMP_DIR"
exit 0
