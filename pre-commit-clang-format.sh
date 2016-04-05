#!/bin/bash
#
# git pre-commit hook that runs a clang-format stylecheck.
#
# This file is part of a set of unofficial pre-commit hooks available
# at github.
# Link:    https://github.com/githubbrowser/Pre-commit-hooks
# Contact: David Martin, david.martin.mailbox@googlemail.com
#
# Modifications for clang-format by rene.milk@wwu.de
# Features:
#  - abort commit when commit does not comply with the style guidelines
#  - create a patch of the proposed style changes
# Link: https://github.com/sawenzel/VecGeom/blob/master/hooks/pre-commit-clang-format
#
# Improvements:
#  - apply patch to the index as well as working tree
#  - save configuration to avoid prompting on each commit 
#  - use coloured diff if available
# By @muendelezaji, Mar 2016

##################################################################
# SETTINGS
# set path to clang-format binary
# CLANG_FORMAT="/usr/bin/clang-format"
CLANG_FORMAT="`type -p clang-format`"

# set path to colordiff binary or equivalent
# COLOR_DIFF="/usr/bin/colordiff"
COLOR_DIFF="$(type -p colordiff)"

# remove any older patches from previous commits. Set to true or false.
# DELETE_OLD_PATCHES=false
DELETE_OLD_PATCHES=false

# only parse files with the extensions in FILE_EXTS. Set to true or false.
# if false every changed file in the commit will be parsed with clang-format.
# if true only files matching one of the extensions are parsed with clang-format.
# PARSE_EXTS=true
PARSE_EXTS=true

# file types to parse. Only effective when PARSE_EXTS is true.
FILE_EXTS=".c .h .cpp .hpp"
# FILE_EXTS=".c .h .cpp .hpp .cc .hh .cxx"

##################################################################
# There should be no need to change anything below this line.

# Reference: http://stackoverflow.com/questions/1055671/how-can-i-get-the-behavior-of-gnus-readlink-f-on-a-mac
canonicalize_filename () {
    local target_file=$1
    local physical_directory=""
    local result=""

    # Need to restore the working directory after work.
    pushd `pwd` > /dev/null

    cd "$(dirname "$target_file")"
    target_file="`basename $target_file`"

    # Iterate down a (possible) chain of symlinks
    while [ -L "$target_file" ]
    do
        target_file=$(readlink "$target_file")
        cd "$(dirname "$target_file")"
        target_file=$(basename "$target_file")
    done

    # Compute the canonicalized name by finding the physical path
    # for the directory we're in and appending the target file.
    physical_directory="`pwd -P`"
    result="$physical_directory"/"$target_file"

    # restore the working directory after work.
    popd > /dev/null

    echo "$result"
}

# exit on error
set -e

# check whether the given file matches any of the set extensions
matches_extension() {
    local filename=$(basename "$1")
    local extension=".${filename##*.}"
    local ext

    for ext in $FILE_EXTS; do [ "$ext" == "$extension" ] && return 0; done

    return 1
}

# necessary check for initial commit
if git rev-parse --verify HEAD >/dev/null 2>&1 ; then
    against=HEAD
else
    # Initial commit: diff against an empty tree object
    # See http://stackoverflow.com/questions/9765453/gits-semi-secret-empty-tree
    against=`git hash-object -t tree /dev/null` # 4b825dc642cb6eb9a060e54bf8d69288fbee4904
fi

if [ ! -x "$CLANG_FORMAT" ] ; then
    printf "Error: clang-format executable not found.\n"
    printf "Set the correct path in $(canonicalize_filename "$0").\n"
    exit 1
fi

# create a random filename to store our generated patch
tmpdir="${TMPDIR:-/tmp}"
prefix="pre-commit-clang-format"
suffix="$(date +%Y%m%d-%H%M%S)"
patch="$tmpdir/$prefix-$suffix.patch"

# clean up any older clang-format patches
$DELETE_OLD_PATCHES && rm -f /tmp/$prefix*.patch

# create one patch containing all changes to the files
git diff-index --cached --diff-filter=ACMR --name-only $against -- | while read file;
do
    # ignore file if we do check for file extensions and the file
    # does not match any of the extensions specified in $FILE_EXTS
    if $PARSE_EXTS && ! matches_extension "$file"; then
        continue;
    fi

    # clang-format our sourcefile, create a patch with diff and append it to our $patch
    # The sed call is necessary to transform the patch from
    #    --- $file timestamp
    #    +++ - timestamp
    # to both lines working on the same file and having a a/ and b/ prefix.
    # Else it can not be applied with 'git apply'.
    # "$CLANG_FORMAT" -style=file "$file" | \
    #     diff -u "$file" - | \
    #     sed -e "1s|--- |--- a/|" -e "2s|+++ -|+++ b/$file|" >> "$patch"

    # clang-format our sourcefile, create a patch with diff and append it to our $patch
    # The sed call is necessary to transform the 'b/-' to 'b/$file' in these lines:
    #   diff --git a/src/hello.cpp b/-
    #   +++ b/-
    # Else it can not be applied with 'git apply'.
    "$CLANG_FORMAT" -style=file "$file" | \
        git diff --no-color --no-index "$file" - | \
        sed -e "1s# b/-# b/$file#" -e "4s#+++ b/-#+++ b/$file#" >> "$patch"
done

# if no patch has been generated all is ok, clean up the file stub and exit
if [ ! -s "$patch" ] ; then
    printf "Files in this commit comply with the clang-format rules.\n"
    rm -f "$patch"
    exit 0
fi

# Apply changes to files in working tree and update index 
function apply_and_stage {
    local patch_file="$1"
    git apply --index "$patch_file"
    # git apply --stat "$patch_file" | head -n -1 | awk '{print $1}' | xargs git add -u "$file"
}

# check config if user wants to skip 'do you want to apply patch' prompt
branch_name=$(git symbolic-ref --short HEAD)
if [ "$(git config --get branch.$branch_name.clangFormatOnCommit)" = always ]; then
    printf "Git config set to always apply clang formatted patch. Applying...\n"
    apply_and_stage "$patch"
    exit 0 # Done successfully
fi

# a patch has been created, notify the user and exit
printf "\nThe following differences were found between the code to commit "
printf "and the clang-format rules:\n\n"
# use colordiff if available
if [ -x "$COLOR_DIFF" ]; then
    cat "$patch" | "$COLOR_DIFF"
else
    cat "$patch"
    printf "\nTip: Install colordiff to get better diff output\n"
fi

# Allows us to read user input below, assigns stdin to keyboard
exec < /dev/tty

while true; do
    printf "\nDo you want to install patch?\n"
    printf "    Yes - commit with patch,\n"
    printf "    Always - assume yes (don't ask again for this branch),\n"
    printf "    No - commit without patch,\n"
    printf "    Cancel - stop committing. "
    read -p "[Y/A/N/C] ? => " answer
        case $answer in
            [Yy] )  apply_and_stage "$patch";
                    break
            ;;
            [Aa] )  apply_and_stage "$patch";
                    # Save config to no longer prompt for this branch
                    git config --add branch.$branch_name.clangFormatOnCommit always;
                    printf "\nAutomatic clang formatting is now enabled for this branch.\n"
                    printf "You will no longer be prompted to re-format code on checkin.\n";
                    printf "To reset this, remove the 'branch.$branch_name.clangFormatOnCommit'\n";
                    printf "option from your repo's gitconfig (normally GIT_DIR/config)\n";
                    break
            ;;
            [Nn] )  printf "\nYou can apply these changes with:\n    git apply $patch\n";
                    printf "(may need to be called from the root directory of your repository)\n\n";
                    printf "Aborting commit. Apply changes and commit again or skip checking with";
                    printf " --no-verify (not recommended).\n";
                    printf "###############################\n";
                    exit 1
            ;;
            [Cc] )  exit 1
            ;;
            * ) echo "Please select a valid choice."
            ;;
    esac
done
