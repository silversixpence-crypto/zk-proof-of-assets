############################################
################ EXECUTOR ##################
############################################

# Format for the `time` command (see `man time` for more details).
export TIME="STATS: time ([H:]M:S) %E ; mem %KKb ; cpu %P"

# snarkjs requires lots of memory.
export NODE_OPTIONS="--max-old-space-size=200000"

# Time command with backslash prefix:
# https://unix.stackexchange.com/questions/497094/time-not-accepting-arguments
function execute {
    ERR_MSG="ERROR $MSG"
    printf "\n================ $MSG ================\n"
    date
    \time --quiet "${@:1}"
    ERR_MSG="UNKNOWN"
}
