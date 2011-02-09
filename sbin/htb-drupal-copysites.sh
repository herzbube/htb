#!/bin/bash
#
# This script is intended to be used when upgrading from one version
# of Drupal to the next. Its purpose is to copy all site-related
# data in the file system and in the database from the previous
# version of Drupal to the next.
#
# To achieve this, this script interactively queries the user for
# some input, e.g. database user passwords etc. Where possible
# sensible defaults are provided.
#
# By default, the current Drupal location is expected to reside
# in /var/www/drupal, and the new Drupal location is expected to
# reside in /var/www/drupal-new. Both locations are expected to be
# symlinks to real directories that obey the name scheme "drupal-x.y".
# All default values offered during the interactive part of this
# script are derived from these directory names.
#
# In detail, this script performs the following steps:
# 1) Copy every site directory from the old Drupal directory to
#    the new.
# 2) Update settings.php for every site
# 3) Create a database dump for every old Drupal site database
#    (e.g. drupal68_herzbube). The files are gzipped and stored
#    in the current directory
# 4) Grant privileges to the Drupal database user for every new
#    Drupal site database (e.g. drupal614_herzbube).
# 5) Create the new Drupal site database and copy its content
#    from the database dump made in step 3
# 6) Leave a backup of the original settings.php file and a
#    compressed version of the database dump in the new site
#    directory


# ------------------------------------------------------------
# Interactively query the user.
#
# Parameters:
#  prompt = String that should be used as the prompt
#  default = The default answer (no default = empty string)
#  echo = value "1" if user should see what she types
#         value "0" if not
#
# Return codes:
#  0 = success
#  1 = failure
#
# On success, the global variable "answer" is set with the
# data entered by the user.
# ------------------------------------------------------------
get_answer()
{
  local prompt="$1"
  local default="$2"
  local echo="$3"
  unset answer

  if test -z "$prompt"; then
    return 1
  fi
  if test -n "$default"; then
    prompt="$prompt [$default]"
  fi
  prompt="${prompt}: "

  local silent_arg
  if test "$echo" = "0"; then
    silent_arg="-s"
  fi

  unset answer
  read $silent_arg -p "$prompt" answer
  if test -z "$answer"; then
    answer="$default"
  fi
}

# ------------------------------------------------------------
# Interactively query the user for the password of a given
# database user. Test the connection and return only if the
# test is successful.
#
# Parameters:
#  prompt = String that should be used as the prompt
#  user = The name of the database user
#
# Return codes:
#  0 = success
#  1 = failure
#
# On success, the global variable "passwd" is set with the
# password entered by the user.
# ------------------------------------------------------------
get_passwd()
{
  local prompt="$1"
  local user="$2"
  unset passwd

  if test -z "$prompt" -o -z "$user"; then
    return 1
  fi

  while :; do
    get_answer "$prompt" "" 0
    if test $? -ne 0; then
      return 1
    fi
    local iter_passwd="$answer"
    printf "  Testing connection... "
    if test -n "$iter_passwd"; then
      echo "do 0;" | mysql -u $user -p"$iter_passwd" 2>/dev/null
    else
      echo "do 0;" | mysql -u $user 2>/dev/null
    fi
    if test $? -eq 0; then
      echo "success"
      passwd="$iter_passwd"
      break
    else
      echo "failure"
    fi
  done

  return 0
}

# ------------------------------------------------------------
# Determine a Drupal version from the name of the directory that
# the given symbolic link points to.
#
# Parameters:
#  symlink = path to a symlink that points to a Drupal directory
#            with the name pattern "drupal-x.y"
#
# Return codes:
#  0 = success
#  1 = failure
#
# On success, the global variable "drupal_ver" is set. For
# instance, if the symlink points to a directory named
# "drupal-6.14", is set to "6.14".
# ------------------------------------------------------------
get_version_from_symlink()
{
  local inst_dir="$1"
  unset drupal_ver

  if test -z "$inst_dir"; then
    return 1
  fi

  # Is it a symbolic link (we don't care if the link target exists)
  if test ! -L "$inst_dir"; then
    return 1
  fi
  local link_target="$(readlink $inst_dir)"
  if test $? -ne 0; then
    return 1
  fi
  # Assume that the target directory name has the pattern "drupal-x.y".
  drupal_ver="$(echo "$link_target" | sed -e 's/^drupal-//')"
  return $?
}

# ------------------------------------------------------------
# Convert a Drupal version into a database prefix.
#
# Parameters:
#  version = Drupal version
#
# Return codes:
#  0 = success
#  1 = failure
#
# On success, the global variable "drupal_db_prefix" is set. For
# instance, if the Drupal version is "6.14", drupal_db_prefix
# is set to "614" (without the dots).
# ------------------------------------------------------------
get_db_prefix_from_version()
{
  local version="$1"
  unset drupal_db_prefix

  if test -z "$version"; then
    return 1
  fi

  drupal_db_prefix="drupal$(echo "$version" | sed -e 's/[^0-9]//')_"
  return $?
}

# ------------------------------------------------------------
# Interactively query user for information about a Drupal
# installation.
#
# Parameters:
#  inst_dir = default installation location
#  inst_name = name of the installation (only used for display)
#
# Return codes:
#  0 = success
#  1 = failure
#
# On success, the global variables "drupal_inst_loc",
# "drupal_inst_ver" and "drupal_db_prefix" are set.
# ------------------------------------------------------------
get_drupal_info()
{
  local default_inst_loc="$1"
  local inst_name="$2"
  unset drupal_inst_loc drupal_inst_ver drupal_db_prefix

  if test -z "$default_inst_loc" -o -z "$inst_name"; then
    return 1
  fi

  get_answer "Location of $inst_name Drupal installation" "$default_inst_loc"
  if test $? -ne 0; then
    return 1
  fi
  drupal_inst_loc="$answer"
  get_version_from_symlink "$drupal_inst_loc"
  if test $? -ne 0; then
    echo "Problem with installation location: does not exist, is not a symlink, or does not point to a directory with a valid name"
    return 1
  fi
  local default_drupal_ver="$drupal_ver"
  get_answer "Version of $inst_name Drupal installation" "$default_drupal_ver"
  if test $? -ne 0; then
    return 1
  fi
  drupal_inst_ver="$answer"
  get_db_prefix_from_version "$drupal_inst_ver"
  if test $? -ne 0; then
    echo "Problem with Drupal version: cannot convert into database prefix"
    return 1
  fi
  local default_drupal_db_prefix="$drupal_db_prefix"
  get_answer "Database prefix of $inst_name Drupal installation" "$default_drupal_db_prefix"
  if test $? -ne 0; then
    return 1
  fi
  drupal_db_prefix="$answer"

  return 0
}

# ------------------------------------------------------------
# Interactively query user for information about a database
# user.
#
# Parameters:
#  username = default user name
#  desc = description of the user (only used for display)
#
# Return codes:
#  0 = success
#  1 = failure
#
# On success, the global variables "db_user_name" and
# "db_user_passwd" are set.
# ------------------------------------------------------------
get_db_user_info()
{
  local default_user_name="$1"
  local user_desc="$2"
  unset db_user_name db_user_passwd

  if test -z "$default_user_name" -o -z "$user_desc"; then
    return 1
  fi


  get_answer "Name of $user_desc database user" "$default_user_name"
  if test $? -ne 0; then
    return 1
  fi
  db_user_name="$answer"
  get_passwd "Enter password for $user_desc database user" "$db_user_name"
  if test $? -ne 0; then
    return 1
  fi
  db_user_passwd="$passwd"

  return 0
}

# ------------------------------------------------------------
# Interactively query user for information about Drupal sites
# to copy from one Drupal installation to the next. Sites are
# auto-detetcted within the Drupal installation's "sites"
# directory.
#
# Parameters:
#  inst_dir = installation location
#
# Return codes:
#  0 = success
#  1 = failure
#
# On success, the global variable "site_and_db_list" is set.
# Each element of the list consists of two values, separated
# by ";". The first value is the site name (a directory name",
# the second value is the database name (without the prefix).
# ------------------------------------------------------------
get_site_info()
{
  local inst_loc="$1"
  local site
  local default_site_list
  local site_list
  local db
  local default_db_list
  local db_list
  unset site_and_db_list

  if test -z "$inst_loc" -o ! -d "$inst_loc"; then
    return 1
  fi
  local sites_dir="$inst_loc/sites"
  if test ! -d "$sites_dir"; then
    echo "No sites directory found in Drupal installation $inst_loc"
    return 1
  fi

  # Auto-detect sites (use all directories except "all", "default"
  # and upgrade sites)
  cd "$sites_dir"
  for site in *; do
    if test ! -d "$site"; then
      continue
    fi
    case "$site" in
      all) continue ;;
      default) continue ;;
      $upgrade_site_prefix.*) continue;;
      *) ;;
    esac
    if test -z "$default_site_list"; then
      default_site_list="$site"
    else
      default_site_list="$default_site_list $site"
    fi
  done
  cd - >/dev/null 2>&1

  get_answer "List of sites to copy" "$default_site_list"
  if test $? -ne 0; then
    return 1
  fi
  site_list="$answer"

  for site in $site_list; do
    local site_dir="$sites_dir/$site"
    if test ! -d "$site_dir"; then
      echo "Site directory $site_dir does not exist"
      return 1
    fi
    # Remove TLD from domain (e.g. "herzbube.ch" becomes "herzbube")
    db="$(echo "$site" | sed -e 's/\.[^.]*$//')"
    if test -z "$default_db_list"; then
      default_db_list="$db"
    else
      default_db_list="$default_db_list $db"
    fi
  done

  get_answer "List of databases to copy (db names without prefix)" "$default_db_list"
  if test $? -ne 0; then
    return 1
  fi
  db_list="$answer"

  # Convert site and db lists into a single list, where the first element of
  # the site list is combined with the first element of the db list, etc.
  # The elements are separated by ";".
  local iter_site=0
  for site in $site_list; do
    local iter_db=$iter_site
    for db in $db_list; do
      if test $iter_db -eq 0; then
        break
      fi
      iter_db=$(expr $iter_db - 1)
    done
    iter_site=$(expr $iter_site + 1)
    site_and_db_list="$site_and_db_list $site;$db"
  done

  return 0
}

# ------------------------------------------------------------
# Main program
# ------------------------------------------------------------

# Define default values and other stuff
my_name="$(basename $0)"
tmp_file="/tmp/$my_name.$$"
base_dir="/var/www"
default_settings_file="default.settings.php"
site_settings_file="settings.php"
default_current_inst_loc="$base_dir/drupal"
default_new_inst_loc="$base_dir/drupal-new"
default_admin_db_user_name=root
default_drupal_db_user_name=drupal
upgrade_site_prefix=site-upgrade

# Gather information about current and new Drupal installation
get_drupal_info "$default_current_inst_loc" "current"
if test $? -ne 0; then
  exit 1
fi
current_drupal_inst_loc="$drupal_inst_loc"
current_drupal_inst_ver="$drupal_inst_ver"
current_drupal_db_prefix="$drupal_db_prefix"
printf "\n"
get_drupal_info "$default_new_inst_loc" "new"
if test $? -ne 0; then
  exit 1
fi
new_drupal_inst_loc="$drupal_inst_loc"
new_drupal_inst_ver="$drupal_inst_ver"
new_drupal_db_prefix="$drupal_db_prefix"

# Gather information about database users
printf "\n"
get_db_user_info "$default_admin_db_user_name" "admin"
if test $? -ne 0; then
  exit 1
fi
admin_db_user_name="$db_user_name"
admin_db_user_passwd="$db_user_passwd"
printf "\n"
get_db_user_info "$default_drupal_db_user_name" "Drupal"
if test $? -ne 0; then
  exit 1
fi
drupal_db_user_name="$db_user_name"
drupal_db_user_passwd="$db_user_passwd"

# Gather information about sites to copy
# (sets site_and_db_list)
printf "\n"
get_site_info "$current_drupal_inst_loc"
if test $? -ne 0; then
  exit 1
fi

# Iterate sites
printf "\n"
for site_and_db in $site_and_db_list; do
  site_name="$(echo "$site_and_db" | awk -F";" '{print $1}')"
  db_name="$(echo "$site_and_db" | awk -F";" '{print $2}')"
  upgrade_site_name="$upgrade_site_prefix.$site_name"
  echo "Processing site $site_name (database $db_name)..."

  current_site_loc="$current_drupal_inst_loc/sites/$site_name"
  new_site_loc="$new_drupal_inst_loc/sites/$site_name"
  upgrade_site_loc="$current_drupal_inst_loc/sites/$upgrade_site_name"
  current_drupal_db_name="${current_drupal_db_prefix}${db_name}"
  new_drupal_db_name="${new_drupal_db_prefix}${db_name}"
  new_site_settings_file="$new_site_loc/$site_settings_file"
  upgrade_site_settings_file="$upgrade_site_loc/$site_settings_file"
  dump_file="$new_site_loc/$current_drupal_db_name.mysqldump"

  # ----------
  echo "  Copying site directory"
  if test -d "$new_site_loc"; then
    get_answer "    Site directory already exists at new location $new_site_loc, overwrite?" "y"
    if test $? -ne 0 -o "$answer" != "y"; then
      echo "    Skipping site"
      continue
    fi
    echo "    Deleting site directory $new_site_loc"
    rm -rf "$new_site_loc"
  fi
  cp -Rp "$current_site_loc" "$new_site_loc"

  # ----------
  echo "  Setting up database connection"
  if test -f "$new_site_settings_file"; then
    echo "    Backing up old $site_settings_file"
    mv "$new_site_settings_file" "$new_site_settings_file.old"
  fi
  echo "    Copying new default $site_settings_file"
  cp "$new_drupal_inst_loc/sites/default/$default_settings_file" "$new_site_settings_file.org"
  cat << EOF >"$tmp_file"
{
  if (\$0 ~ /^\\\$db_url = /)
  {
    print "\$db_url = 'mysqli://" drupal_db_user_name ":" drupal_db_user_passwd "@localhost/" new_drupal_db_name "';"
  }
  else
  {
    print \$0
  }
}
EOF
  cat "$new_site_settings_file.org" | awk -f "$tmp_file" drupal_db_user_name="$drupal_db_user_name" drupal_db_user_passwd="$drupal_db_user_passwd" new_drupal_db_name="$new_drupal_db_name" >"$new_site_settings_file"
  echo "    Restricting permissions"
  chown www-data "$new_site_settings_file"
  chmod 400 "$new_site_settings_file"

  # ----------
  echo "  Creating temporary upgrade site"
  if test -d "$upgrade_site_loc"; then
    echo "    Upgrade site directory $upgrade_site_loc already exists, overwriting"
    rm -rf "$upgrade_site_loc"
  fi
  cp -Rp "$current_site_loc" "$upgrade_site_loc"
  if test ! -f "$upgrade_site_settings_file"; then
    echo "    Upgrade site has no $site_settings_file, please configure manually !!!"
  else
    mv "$upgrade_site_settings_file" "$upgrade_site_settings_file.old"
    cat "$upgrade_site_settings_file.old" | awk -f "$tmp_file" drupal_db_user_name="$drupal_db_user_name" drupal_db_user_passwd="$drupal_db_user_passwd" new_drupal_db_name="$new_drupal_db_name" >"$upgrade_site_settings_file"
  fi

  # ----------
  echo "  Granting privileges on $new_drupal_db_name"
  echo "revoke all privileges on \`$new_drupal_db_name\`.* from '${drupal_db_user_name}'@'localhost';" | mysql -u $admin_db_user_name -p"$admin_db_user_passwd"
  echo "grant all privileges on \`$new_drupal_db_name\`.* to '${drupal_db_user_name}'@'localhost';" | mysql -u $admin_db_user_name -p"$admin_db_user_passwd"

  # ----------
  echo "  Backing up $current_drupal_db_name to $dump_file"
  mysqldump --add-drop-table -u $drupal_db_user_name -p"$drupal_db_user_passwd" "$current_drupal_db_name" >"$dump_file"

  # ----------
  echo "  Creating $new_drupal_db_name"
  echo "drop database if exists \`$new_drupal_db_name\`;" | mysql -u $drupal_db_user_name -p"$drupal_db_user_passwd"
  echo "create database if not exists \`$new_drupal_db_name\`;" | mysql -u $drupal_db_user_name -p"$drupal_db_user_passwd"
  mysql -u $drupal_db_user_name -p"$drupal_db_user_passwd" "$new_drupal_db_name" <"$dump_file"

  # ----------
  echo "  Compressing $dump_file"
  gzip -f "$dump_file"
done
