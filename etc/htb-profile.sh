#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-profile.sh
# | Date:           01 Jan 2011
# | Description:    Contains code that must be run by the login shell, but not
# |                 by sub-shells.
# |
# |                 The best place to invoke this script is either the
# |                 system-wide /etc/profile, or the user-specific ~/.profile.
# |                 These files are also read by other shells than the bash,
# |                 notably /bin/sh.
# |
# |                 Note that this is not a regular script! It must be invoked
# |                 by sourcing it (dot syntax, or the source shell builtin).
# |
# | Arguments:      None
# | Exit codes:     None
# | Dependencies:   bash (export -f)
# =========================================================================


# Set up Fink environment
FINK_INIT_SCRIPT="/sw/bin/init.sh"
if test -r "$FINK_INIT_SCRIPT"; then
  # Do *NOT* source this in .bashrc
  . "$FINK_INIT_SCRIPT"
fi

# Set up HTB environment
# Note: The order in which the following things are run is important
if test -z "$HTB_BASE_DIR"; then
  HTB_BASE_DIR="/usr/local"
fi
HTB_ENV_SCRIPT_PATH="$HTB_BASE_DIR/etc/htb-setenv.sh"
if test -r "$HTB_ENV_SCRIPT_PATH"; then
  . "$HTB_ENV_SCRIPT_PATH"
else
  echo "Unable to find HTB environment (htb-setenv.sh)"
fi
HTB_BASHRC_SCRIPT_PATH="$HTB_BASE_DIR/etc/htb-bashrc.sh"
if test -r "$HTB_BASHRC_SCRIPT_PATH"; then
  . "$HTB_BASHRC_SCRIPT_PATH"  # is not read by a bash login shell
else
  echo "Unable to find HTB environment (htb-bashrc.sh)"
fi
