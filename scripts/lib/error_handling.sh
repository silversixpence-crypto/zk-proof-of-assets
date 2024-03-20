#!/usr/bin/env bash

############################################
########### ERROR HANDLING #################
############################################

# Inspiration taken from
# https://unix.stackexchange.com/questions/462156/how-do-i-find-the-line-number-in-bash-when-an-error-occured
# https://www.gnu.org/software/bash/manual/html_node/Bash-Variables.html

# Change this in sourcing script to get error messages.
ERR_MSG="UNKNOWN"

set -eE -o functrace

failure() {
    local lineno=$2
    local fn=$3
    local exitstatus=$4
    local cmd=$5
    local msg=$6
    local lineno_fns=${1% 0}

    if [[ $exitstatus == 0 ]]; then
        exit 0
    fi

    if [[ "$lineno_fns" != "0" ]] ; then
        lineno="${lineno} ${lineno_fns}"
    fi

    printf "\n####### ERROR #######\n\n"
    echo "  Failure in file:                    ${BASH_SOURCE[1]}"
    echo "  Function trace [line numbers]:      ${fn} [${lineno}]"
    echo "  Exit status:                        ${exitstatus}"
    echo "  Command that failed:                $cmd"
    echo "  Error message:                      $msg"

    exit 1
}
trap 'failure "${BASH_LINENO[*]}" "$LINENO" "${FUNCNAME[*]:-script}" "$?" "$BASH_COMMAND" "$ERR_MSG"' ERR EXIT

