#!/bin/bash

# ------------------------------------------------------------
MYNAME=$(basename $0)
CONF_DIR=/etc/awstats
CONF_FILE_PREFIX="awstats."
CONF_FILE_POSTFIX=".conf"
CONF_FILES_TO_SKIP="awstats.conf"
AWSTATS_EXECUTABLE="/usr/lib/cgi-bin/awstats.pl"

# ------------------------------------------------------------
if test ! -d "$CONF_DIR"; then
  echo "$MYNAME: Configuration directory $CONF_DIR does not exist"
  exit 1
fi
cd "$CONF_DIR"

if test ! -x "$AWSTATS_EXECUTABLE"; then
  echo "$MYNAME: The awstats executable $AWSTATS_EXECUTABLE does not exist or is not executable"
  exit 1
fi

# ------------------------------------------------------------
for CONF_FILE in ${CONF_FILE_PREFIX}*${CONF_FILE_POSTFIX}
do
  SKIP_CONF_FILE=0
  for CONF_FILE_TO_SKIP in $CONF_FILES_TO_SKIP
  do
    if test "$CONF_FILE" = "$CONF_FILE_TO_SKIP"; then
      SKIP_CONF_FILE=1
      break
    fi
  done
  if test $SKIP_CONF_FILE -eq 1; then
    continue
  fi

  VIRTUAL_HOST_NAME=$(echo "$CONF_FILE" | sed -e 's/^'$CONF_FILE_PREFIX'//' -e 's/'$CONF_FILE_POSTFIX'$//')
  $AWSTATS_EXECUTABLE -config="$VIRTUAL_HOST_NAME" -update >/dev/null
done
