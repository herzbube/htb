#!/bin/bash

# ------------------------------------------------------------
# Arguments
#  None
#
# Exit codes
#  0 = ok
#  1 = this program is already running for the current user
#  2 = a prerequisite could not be found
#  3 = some error related to temporary files occurred
# ------------------------------------------------------------


# ------------------------------------------------------------
# Initialize variables

# Maildirs
MAIL_DIR="Maildir"
TRAINING_HAM_DIR=".Junk.Training-ham"
TRAINING_SPAM_DIR=".Junk.Training-spam"
TRAINED_AS_HAM_DIR=".Junk.Trained-as-ham"
TRAINED_AS_SPAM_DIR=".Junk.Trained-as-spam"

# Programs
SA_LEARN_BIN=/usr/bin/sa-learn
SPAMC_BIN=/usr/bin/spamc
MAILDROP_BIN=/usr/bin/maildrop
RM_BIN=/bin/rm
MV_BIN=/bin/mv

# Other variables
TMP_DIR="/tmp/$$"
MAILDROP_FILTER_HAM="$TMP_DIR/maildrop.ham"
MAILDROP_FILTER_SPAM="$TMP_DIR/maildrop.spam"
LOCK_FILE="$HOME/$(basename $0).$LOGNAME.pid"

# ------------------------------------------------------------
# Check if this program is already running for the current user
if test -f "$LOCK_FILE"; then
  exit 1
fi

# ------------------------------------------------------------
# Sanity checks
#for BIN in "$SA_LEARN_BIN" "$SPAMC_BIN" "$MAILDROP_BIN" "$RM_BIN" "$MV_BIN"
for BIN in "$SA_LEARN_BIN" "$SPAMC_BIN" "$RM_BIN" "$MV_BIN"
do
  which "$BIN" >/dev/null 2>&1
  if test $? -ne 0; then
    echo "$BIN could not be found"
    exit 2
  fi
done

# ------------------------------------------------------------
# Setup temporary directory and files within
if test -d $TMP_DIR; then
  echo "Temporary directory $TMP_DIR already exists"
  exit 3
fi
mkdir -p $TMP_DIR
if test $? -ne 0; then
  echo "Could not create temporary directory $TMP_DIR"
  exit 3
fi
echo "to \"\$HOME/$MAIL_DIR/$TRAINED_AS_HAM_DIR\"" >$MAILDROP_FILTER_HAM
echo "to \"\$HOME/$MAIL_DIR/$TRAINED_AS_SPAM_DIR\"" >$MAILDROP_FILTER_SPAM

# ------------------------------------------------------------
# Create lock file. From now on, do not return without removing the file
echo $$ >"$LOCK_FILE"

# ------------------------------------------------------------
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
    if test ! -d "$SRC_DIR" -o ! -d "$DST_DIR"; then
      continue
    fi

    # Learn/re-learn messages
    $SA_LEARN_BIN "--$MESSAGE_TYPE" "$SRC_DIR" 2>&1 | logger

    # 1) Let spamc re-classify message - the message has been learned as the correct
    #    type, so the re-classification should give the correct result; the purpose
    #    of re-classification is to add the correct mail headers to the message, also
    #    removing any wrong headers from a previous classification
    # 2) Use maildrop to deliver the cleaned-up message to the final mailbox folder
    # 3) Remove the original message
#    find "$SUB_DIR" -type f -exec bash -c "$SPAMC_BIN <{} | "$MAILDROP_BIN" $MAILDROP_FILTER; $RM_BIN -f {}" \;
#    find "$SRC_DIR" -type f -exec bash -c "$MV_BIN {} $DST_DIR" \;
  done
done

# ------------------------------------------------------------
# Cleanup
rm -rf "$TMP_DIR"
rm -f "$LOCK_FILE"
