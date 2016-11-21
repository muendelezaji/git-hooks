#!/bin/sh
###--------------------------------------------------------------------------------------------###
#                                                                                                #
# The following section has been adapted from https://github.com/githubbrowser/Pre-commit-hooks  #
#                                                                                                #
# Git pre-commit hook that runs multiple hooks specified in $HOOKS.                              #
#                                                                                                #
# Additions: show hook success/fail status                                                       #
# By @muendelezaji, Mar 2016                                                                     #
###--------------------------------------------------------------------------------------------###

###########################################################
# CONFIGURATION:
# pre-commit hooks to be executed. They should be in the same .git/hooks/ folder
# as this script. Hooks should return 0 if successful and nonzero to cancel the
# commit. They are executed in the order in which they are listed.
# e.g. HOOKS="pre-commit-clang-format pre-commit-protected-branch"
HOOKS=
###########################################################
# There should be no need to change anything below this line.

# exit on error
set -e

# Absolute directory path this script is in
SCRIPT="$(readlink -- "$0")"
SCRIPTPATH="$(dirname -- "$SCRIPT")"

for hook in $HOOKS
do
    echo "----------------------------------------------------------------------"
    echo "Running hook: $hook"
    # run hook if it exists
    # if it returns with nonzero exit with 1 and thus abort the commit
    if [ -f "$SCRIPTPATH/$hook" ]; then
        "$SCRIPTPATH/$hook"
        if [ $? != 0 ]; then
            echo "Hook '$hook' failed."
            exit 1
        fi
        echo 'OK.'
        echo # new line
    else
        echo "Error: file $hook not found."
        echo "Aborting commit. Make sure the hook is in $SCRIPTPATH and executable."
        echo "You can disable it by removing it from the list in $SCRIPT."
        echo "You can skip all pre-commit hooks with --no-verify (not recommended)."
        exit 1
    fi
done
