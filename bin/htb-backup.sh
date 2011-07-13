#!/usr/bin/env bash

# =========================================================================
# | Script name:    htb-backup.sh
# | Date:           13 Jul 2011
# | Description:    Creates backup copies of various system folders. This script
# |                 is tailored for backing up my private Debian system, but
# |                 there remains a slight chance that someone else could find
# |                 it a useful source of inspiration.
# |
# | Arguments:      -h: Print a short help page
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
HTB_USAGE_LINE="$HTB_SCRIPT_NAME [-h]"

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
# Temporary files
TMP_FILE="$HTB_TMP_DIR/$HTB_SCRIPT_NAME.$$"
TMP_EXCLUDE_FILE="$HTB_TMP_DIR/$HTB_SCRIPT_NAME.exclude.$$"
# Backup directories
BACKUP_DIR=/var/backups
MYSQL_BACKUP_DIR=$BACKUP_DIR/mysql
POSTGRESQL_BACKUP_DIR=$BACKUP_DIR/postgresql
LDAP_BACKUP_DIR=$BACKUP_DIR/ldap
GIT_BACKUP_DIR=$BACKUP_DIR/git
ETC_BACKUP_DIR=$BACKUP_DIR/etc
USRLOCAL_BACKUP_DIR=$BACKUP_DIR/usr.local
HOME_BACKUP_DIR=$BACKUP_DIR/home
HOME_EXCLUDE_DIR=exclude
BOOT_BACKUP_DIR=$BACKUP_DIR/boot
VARLIB_BACKUP_DIR=$BACKUP_DIR/var.lib
VARWWW_BACKUP_DIR=$BACKUP_DIR/var.www
VARSAMBA_BACKUP_DIR=$BACKUP_DIR/var.samba

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

if test $# -ne 0; then
  HTB_CLEANUP_AND_EXIT 4 "$HTB_USAGE_LINE"
fi

# +------------------------------------------------------------------------
# | Main program processing
# +------------------------------------------------------------------------

# Add sbin to path if it's not there (during cron, PATH is /bin:/usr/bin)
# At least init script and slapcat need this
if test -z "$(echo $PATH | grep sbin)"; then
  PATH=/sbin:/usr/sbin:$PATH
fi

# Create temporary folder
mkdir -p "$HTB_TMP_DIR"

# ------------------------------------------------------------
# Backup MySQL
# Note: Authentication occurs with username / password taken
# from ~/.my.cnf.
test ! -r ~/.my.cnf && echo "$HTB_SCRIPT_NAME: ~/.my.cnf does not exist or is not readable"
test ! -d $MYSQL_BACKUP_DIR && mkdir -p $MYSQL_BACKUP_DIR
MYSQL_BACKUP_FILE=$MYSQL_BACKUP_DIR/all-databases.sql
mysqldump --all-databases >$MYSQL_BACKUP_FILE
if test $? -ne 0; then
  echo "$HTB_SCRIPT_NAME: mysqldump returned error"
fi

# ------------------------------------------------------------
# Backup PostgreSQL
# Note: PostgreSQL is set up to trust the system user postgres as
# the database super user. Whoever is capable to switch user or sudo
# to postgres may act as the super user. Normally only root can do
# this.
test ! -d $POSTGRESQL_BACKUP_DIR && mkdir -p $POSTGRESQL_BACKUP_DIR
POSTGRESQL_BACKUP_FILE=$POSTGRESQL_BACKUP_DIR/all-databases.sql
sudo -u postgres pg_dumpall >$POSTGRESQL_BACKUP_FILE
if test $? -ne 0; then
  echo "$HTB_SCRIPT_NAME: pg_dumpall returned error"
fi

# ------------------------------------------------------------
# Backup LDAP
# Note: The current database backend is bdb. According to the slapcat
# man page it should be safe to use slapcat with this backend type
# without shutting down slapd. If slapd needs to be shut down, the
# backup code should be wrapped like this:
#   /etc/init.d/slapd stop >/dev/null
#   if test $? -eq 0; then
#     <backup code>
#   fi
#   /etc/init.d/slapd start >/dev/null
#test ! -d $LDAP_BACKUP_DIR && mkdir -p $LDAP_BACKUP_DIR
#LDAP_BACKUP_FILE=$LDAP_BACKUP_DIR/database-1.ldif
#/usr/sbin/slapcat -n 1  >$LDAP_BACKUP_FILE

# ------------------------------------------------------------
# Backup Git
test ! -d $GIT_BACKUP_DIR && mkdir -p $GIT_BACKUP_DIR
cd /srv/gitosis/repositories
if test $? -eq 0; then
  for GIT_REPO in *
  do
    GIT_BACKUP_FILE=$GIT_BACKUP_DIR/$GIT_REPO.tar
    tar cfp $GIT_BACKUP_FILE ./$GIT_REPO
#    svnadmin --quiet --deltas dump $SVN_REPO >$SVN_BACKUP_FILE
#    if test $? -ne 0; then
#      echo "$HTB_SCRIPT_NAME: svnadmin returned error"
#    fi
  done
fi

# ------------------------------------------------------------
# Backup /etc directory
test ! -d $ETC_BACKUP_DIR && mkdir -p $ETC_BACKUP_DIR
cd /
tar cfp $ETC_BACKUP_DIR/etc.tar ./etc
cd - >/dev/null

# ------------------------------------------------------------
# Backup /usr/local directory
test ! -d $USRLOCAL_BACKUP_DIR && mkdir -p $USRLOCAL_BACKUP_DIR
cd /
# Prepare a file that contains a list with files to archive.
# Of course, it would be preferrable to use direct shell file
# name patterns with tar, such as the following command line:
# tar cfp $USRLOCAL_BACKUP_DIR/usr.local.tar ./usr/local/lib/*.sh ./usr/local/cron ./usr/local/etc ./usr/local/lib/*.awk ./usr/local/lib/*.pl ./usr/local/ssl
# Unfortunately, in some cases a file name pattern might not match
# any file, which makes tar abort with an error.
rm -f $TMP_FILE
test -d ./usr/local/cron && find ./usr/local/cron >>$TMP_FILE
test -d ./usr/local/etc && find ./usr/local/etc >>$TMP_FILE
test -d ./usr/local/lib && find ./usr/local/lib -type f -name '*.sh' >>$TMP_FILE
test -d ./usr/local/lib && find ./usr/local/lib -type f -name '*.awk' >>$TMP_FILE
test -d ./usr/local/lib && find ./usr/local/lib -type f -name '*.pl' >>$TMP_FILE
test -d ./usr/local/ssl && find ./usr/local/ssl >>$TMP_FILE
if test -s $TMP_FILE; then
  tar cfp $USRLOCAL_BACKUP_DIR/usr.local.tar --files-from $TMP_FILE
fi
cd - >/dev/null

# ------------------------------------------------------------
# Backup /home and /root directories, but only if the tar
# file does not exist yet (will be rotated away on a weekly basis)
test ! -d $HOME_BACKUP_DIR && mkdir -p $HOME_BACKUP_DIR
if test ! -f $HOME_BACKUP_DIR/home.tar; then
  # Prepare a file that contains a list with directories
  # that should be excluded from the backup. We have to
  # explicitly name each exclude directory, without using
  # the '*' wildcard. Of course, it would be preferrable
  # to use tar's --exclude option together with '*'
  # (e.g. --exclude ./home/*/exclude), but this is not
  # possible because tar treats the '*' wildcard in a
  # "greedy" (as known from regexp) way.
  rm -f $TMP_EXCLUDE_FILE
  for home_dir in ./home/* ./root
  do
     echo $home_dir/$HOME_EXCLUDE_DIR >>$TMP_EXCLUDE_FILE
  done

  cd /
  rm -f $TMP_FILE
  # Exclude sockets
  find ./home ! -type s >>$TMP_FILE
  find ./root ! -type s >>$TMP_FILE
  # Use --no-recursion because find already did the recursion for us
  # and TMP_FILE therefore contains directory names
  tar cfp $HOME_BACKUP_DIR/home.tar --files-from $TMP_FILE --exclude-from $TMP_EXCLUDE_FILE --no-recursion
  cd - >/dev/null
fi

# ------------------------------------------------------------
# Backup /boot directory
test ! -d $BOOT_BACKUP_DIR && mkdir -p $BOOT_BACKUP_DIR
if test ! -f $BOOT_BACKUP_DIR/boot.tar; then
  cd /
  tar cfp $BOOT_BACKUP_DIR/boot.tar ./boot/config*
  cd - >/dev/null
fi

# ------------------------------------------------------------
# Backup several directories in /var/lib
test ! -d $VARLIB_BACKUP_DIR && mkdir -p $VARLIB_BACKUP_DIR
cd /
# Stop daemons
/etc/init.d/collectd stop
# Prepare a file that contains a list with files to archive.
# Of course, it would be preferrable to use direct shell file
# name patterns with tar, such as the following command line:
# tar cfp $VARLIB_BACKUP_DIR/var.lib.tar ./var/lib/mailman/archives ./var/lib/squirrelmail ./var/lib/zope2.8
# Unfortunately, some directories contain special files
# (e.g. sockets), which makes tar spit out a warning or
# error message that is then sent as mail by cron. We want 
# to suppress such unnecessary mails.
rm -f $TMP_FILE
test -d ./var/lib/mailman/archives && find ./var/lib/mailman/archives >>$TMP_FILE
test -d ./var/lib/squirrelmail && find ./var/lib/squirrelmail >>$TMP_FILE
test -d ./var/lib/samba && find ./var/lib/samba >>$TMP_FILE
test -d ./var/lib/collectd && find ./var/lib/collectd >>$TMP_FILE
test -d ./var/lib/mediawiki/images && find ./var/lib/mediawiki/images >>$TMP_FILE
# Exclude sockets
#find ./var/lib/zope2.8 ! -type s >>$TMP_FILE
if test -s $TMP_FILE; then
  # Use --no-recursion because find already did the recursion for us
  # and TMP_FILE therefore contains directory names
  tar cfp $VARLIB_BACKUP_DIR/var.lib.tar --files-from $TMP_FILE --no-recursion
fi
cd - >/dev/null
# Restart daemons
/etc/init.d/collectd start

# ------------------------------------------------------------
# Backup several directories/files in /var/www
test ! -d $VARWWW_BACKUP_DIR && mkdir -p $VARWWW_BACKUP_DIR
cd /
tar cfp $VARWWW_BACKUP_DIR/drupal.tar ./var/www/drupal/.htaccess ./var/www/drupal/sites
tar cfp $VARWWW_BACKUP_DIR/pelargir.herzbube.ch.tar ./var/www/pelargir.herzbube.ch
tar cfp $VARWWW_BACKUP_DIR/www.herzbube.ch.tar ./var/www/herzbube.ch
cd - >/dev/null

# ------------------------------------------------------------
# Backup several directories/files in /var/samba
test ! -d $VARSAMBA_BACKUP_DIR && mkdir -p $VARSAMBA_BACKUP_DIR
cd /
# Prepare a file that contains a list with files to archive.
rm -f $TMP_FILE
find ./var/samba/daten | \
  grep -v "^./var/samba/daten/backup" | \
  grep -v "^./var/samba/daten/cdrom" | \
  grep -v "^./var/samba/daten/lost+found" >>$TMP_FILE
if test -s $TMP_FILE; then
  # Use --no-recursion because find already did the recursion for us
  # and TMP_FILE therefore contains directory names
  tar cfp $VARSAMBA_BACKUP_DIR/var.samba.daten.tar --files-from $TMP_FILE --no-recursion
fi
cd - >/dev/null


HTB_CLEANUP_AND_EXIT 0
