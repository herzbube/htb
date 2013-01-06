----------------------------------------------------------------------
HTB - herzbube's toolbox
----------------------------------------------------------------------
The HTB is a collection of useful programs, usually shell scripts, that I
(herzbube) created for making my work-related tasks a little bit more
comfortable. Some programs were also created to improve system administration
of my private Linus server.

HTB tries to be system independent, but this probably is an illusion.


----------------------------------------------------------------------
How does it work?
----------------------------------------------------------------------
The HTB assumes that there is the following directory structure below an
install base directory:

install-base
  bin
  cron
  etc
  include
  lib
  man
  sbin
  share
  src

A common install base directory for the HTB is /usr/local.

To make the HTB accessible on the command line, the following folders must be
in the PATH:
- $HTB_BASE_DIR/bin
- $HTB_BASE_DIR/sbin (if the user is root)

All HTB scripts rely on a few things that are set up in the so-called
"HTB environment":
- A HTB script assumes that the environment is properly set up if the
  environment variable HTB_ENVIRONMENT_INCLUDED is set
- If not, a HTB script tries to set up the HTB environment by invoking
  htb-setenv.sh (hardcoded name)
- If the environment variable HTB_BASE_DIR is set, htb-setenv.sh must be
  located in a directory "etc" below the folder referred to by this variable
- If HTB_BASE_DIR is not set, the HTB script looks for htb-setenv.sh in the
  folder "etc" that lies in parallel to its own location

----------------------------------------------------------------------
Shell environment integration
----------------------------------------------------------------------
Assuming that the HTB files are installed in /usr/local, add the following line to your
~/.profile (or the system-wide /etc/profile) to integrate he HTB into your login shell:
  . /usr/local/etc/htb-profile.sh

Add the following line to your ~/.bashrc to propagate the integration to subshells:
  . /usr/local/etc/htb-bashrc.sh

Notes
- If the .bashrc modification is not made, then aliases and functions are not available
  in subshells
- htb-profile.sh automatically invokes htb-bashrc.sh

----------------------------------------------------------------------
Dependencies
----------------------------------------------------------------------
HTB requires the following utilities (not an exclusive list):
- /usr/bin/env; all the other stuff is expected to be in the PATH
- bash
- cp, rm, ln, ls
- pwd, basename, dirname
- fgrep, grep, egrep
- sed, awk
- cat, head, tail, cut, sort, uniq
- tty (if this prints "not a tty" the HTB script assumes that it runs without
  a connection to a terminal, usually in a cron context)
- exec
- id
- less


----------------------------------------------------------------------
Coding guidelines
----------------------------------------------------------------------
- All scripts use the prefix "htb-" in their name so as to minimize collision
  with other scripts
- All scripts use a suffix in their name that indicates their type;
  specifically .sh, .pl, .awk, .sed
- All scripts use /usr/bin/env in the shebang
- If possible line length should not exceed 75 characters; this is not an
  absolute requirement, except for all comment material
- Indentation is 2 spaces (no tabs)
- Use "test" not []
- Put "then" and "do" on the same line as "if" and "while" or "for" (separated
  by ;), not on a new line
- Function names are prefixed with "HTB_", all upper case, words separated
  by "_" (e.g. HTB_CLEANUP_AND_EXIT)
- Global variable names: see function names (e.g. HTB_ENVIRONMENT_INCLUDED)
- Local variable names: same as global variable names, except that they do not
  need to be prefixed with "HTB_"
- Script anatomy
  - shebang
  - script header
  - lead-in for functions
  - functions
  - lead-in for main program
  - section "Variable declaration and initialisation"
  - section "Argument processing"
  - section "Main program processing"
- Every script has a header whose purpose is to explain at a glance what the
  script does; this duplicates the usage function, but I just like this
- Script header fields are
  - Script name: The base file name of the script
  - Date: The date when the script initially was written
  - Purpose: Explanation of what the script does
  - Arguments: Enumeration and explanation of the arguments of the script
  - Return values: Enumeration and explanation of the return values of the
    script
  - Dependencies: Enumeration of the script's relevant dependencies. At least
    all other HTB scripts invoked must appear here.
- Every function has a header with the following fields
  - Unnamed: Explains the purpose of the function, if necessary in detail
  - Arguments: Enumeration and explanation of the arguments of the function
  - Return values: Enumeration and explanation of the return values of the
    function
  - Global variables used
  - Global functions called
  - HTB scripts invoked
- Variables should always be expanded within double quotes, unless this
  causes problems for some reason (document these reasons if not obvious)
- Always try to work with absolute path names so that accidental cd's have
  no effect
- If you use an absolute path name, do not count on it to be "pretty" (i.e. it
  can be something like "/usr/local/bin/../etc")
- On the other hand do not cd unless absolutely necessary, and if you do then
  switch back to the original working directory as soon as possible
- Suffix "_DIR" indicates an absolute or relative reference to a directory
  (often the result of dirname), suffix "_NAME" indicates a plain file name
  (often the result of basename), suffix "_PATH" indicates an absolute path
  to either a directory or a file


----------------------------------------------------------------------
Interfaces
----------------------------------------------------------------------
- Every script must define the following functions
  - HTB_CLEANUP_AND_EXIT
  - HTB_PRINT_USAGE
- Every script must define the following variables
  - HTB_BASE_DIR (absolute; this is required by the HTB environment setup
    script htb-setenv.sh)
  - HTB_SCRIPT_NAME
  - HTB_SCRIPT_DIR (absolute)
  - HTB_USAGE_LINE
- Common script exit codes (not all scripts have the same exit codes)
 0: No error
 1: Aborted by user interaction
 2: Aborted by signal (e.g. Ctrl+C)
 3: Error during initialisation
 4: Error while checking arguments
 >=5: Error during main program
- Function return values
 0: ok
 >=1: notok
- The environment provides
  - HTB_TMP_DIR
    - an absolute path to a unique temp directory that belongs entirely to
      the script (usually somewhere in /tmp)
    - the environment provides the name only; if the script wants to use the
      directory, it has to mkdir on its own
    - if the script creates the dir, it is also expected to destroy the dir
      (usually in HTB_CLEANUP_AND_EXIT)
