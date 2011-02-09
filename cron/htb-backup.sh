# General variables
MYNAME=$(basename $0)
MAILUSER=patrick

# Add sbin to path if it's not there (during cron, PATH is /bin:/usr/bin)
# At least init Script and slapcat need this
if test -z "$(echo $PATH | grep sbin)"; then
  PATH=/sbin:/usr/sbin:$PATH
fi

# Set directories
TMP_FILE=/tmp/$(basename $0).$$
TMP_EXCLUDE_FILE=/tmp/$(basename $0).exclude.$$
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

# ------------------------------------------------------------
# Backup MySQL
# Note: Authentication occurs with username / password taken
# from ~/.my.cnf.
test ! -d $MYSQL_BACKUP_DIR && mkdir -p $MYSQL_BACKUP_DIR
MYSQL_BACKUP_FILE=$MYSQL_BACKUP_DIR/all-databases.sql
mysqldump --all-databases >$MYSQL_BACKUP_FILE
if test $? -ne 0; then
  echo "$MYNAME: mysqldump returned error" | mail -s "$MYNAME" $MAILUSER
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
  echo "$MYNAME: pg_dumpall returned error" | mail -s "$MYNAME" $MAILUSER
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
test ! -d $LDAP_BACKUP_DIR && mkdir -p $LDAP_BACKUP_DIR
LDAP_BACKUP_FILE=$LDAP_BACKUP_DIR/database-1.ldif
/usr/sbin/slapcat -n 1  >$LDAP_BACKUP_FILE

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
#      echo "$MYNAME: svnadmin returned error" | mail -s "$MYNAME" $MAILUSER
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
find ./usr/local/cron >>$TMP_FILE
find ./usr/local/etc >>$TMP_FILE
find ./usr/local/lib -type f -name '*.sh' >>$TMP_FILE
find ./usr/local/lib -type f -name '*.awk' >>$TMP_FILE
find ./usr/local/lib -type f -name '*.pl' >>$TMP_FILE
find ./usr/local/ssl >>$TMP_FILE
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
# Prepare a file that contains a list with files to archive.
# Of course, it would be preferrable to use direct shell file
# name patterns with tar, such as the following command line:
# tar cfp $VARLIB_BACKUP_DIR/var.lib.tar ./var/lib/mailman/archives ./var/lib/squirrelmail ./var/lib/zope2.8
# Unfortunately, some directories contain special files
# (e.g. sockets), which makes tar spit out a warning or
# error message that is then sent as mail by cron. We want 
# to suppress such unnecessary mails.
rm -f $TMP_FILE
find ./var/lib/mailman/archives >>$TMP_FILE
find ./var/lib/squirrelmail >>$TMP_FILE
find ./var/lib/samba >>$TMP_FILE
find ./var/lib/collectd >>$TMP_FILE
find ./var/lib/mediawiki/images >>$TMP_FILE
# Exclude sockets
#find ./var/lib/zope2.8 ! -type s >>$TMP_FILE
if test -s $TMP_FILE; then
  # Use --no-recursion because find already did the recursion for us
  # and TMP_FILE therefore contains directory names
  tar cfp $VARLIB_BACKUP_DIR/var.lib.tar --files-from $TMP_FILE --no-recursion
fi
cd - >/dev/null

# ------------------------------------------------------------
# Backup several directories/files in /var/www
test ! -d $VARWWW_BACKUP_DIR && mkdir -p $VARWWW_BACKUP_DIR
cd /
tar cfp $VARWWW_BACKUP_DIR/drupal.tar ./var/www/drupal/.htaccess ./var/www/drupal/sites
tar cfp $VARWWW_BACKUP_DIR/osgiliath.herzbube.ch.tar ./var/www/osgiliath.herzbube.ch
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

# ------------------------------------------------------------
# Cleanup
rm -f $TMP_FILE
rm -f $TMP_EXCLUDE_FILE
