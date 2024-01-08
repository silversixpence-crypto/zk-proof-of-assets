#!/bin/bash

############################################
########### ERROR HANDLING #################
############################################

# http://stackoverflow.com/questions/35800082/ddg#35800451
set -eE

# call like `graceful_exit <exit_code>`
function graceful_exit {
    printf "\n####### EXITING... #######\n"
    DEFAULT_EXIT_CODE=0
    exit ${1:-$DEFAULT_EXIT_CODE} # use first param or default to 0
}

# Print line number & message of error and exit gracefully
# call like `err_report $LINENO $ERR_MSG`
function err_report {
    ret=$? # previous command exit value
    printf "\n####### A COMMAND FAILED ON LINE $1 #######\n\n"
    echo "Error message: ${@:2}"
    graceful_exit "$ret"
}

# can change this in the functions below to get nicer error messages
# make sure to set back to "UNKNOWN" at end of function scope
ERR_MSG="UNKNOWN"

# global error catcher
trap 'err_report $LINENO $ERR_MSG' ERR

############################################
################ EXECUTOR ##################
############################################

# Time command with backslash prefix:
# https://unix.stackexchange.com/questions/497094/time-not-accepting-arguments

# Format for the `time` command (see `man time` for more details).
export TIME="STATS: time ([H:]M:S) %E ; mem %KKb ; cpu %P"

function execute {
    ERR_MSG="ERROR $MSG"
    printf "\n================ $MSG ================\n"
    date
    \time --quiet "${@:1}"
}

############################################
################# SNARK ####################
############################################

# Circuit compilation commands were originally from yo-sun/circom-pairing:
# https://github.com/yi-sun/circom-pairing/blob/3c43adafa4d908c72f79651a62bd9481fe50fde9/scripts/signature/build_signature.sh
# And this doc:
# https://hackmd.io/@yisun/BkT0RS87q

CIRCUITS_DIR=./circuits
PHASE1=./powersOfTau28_hez_final_22.ptau
BUILD_DIR=./build/batch_ecdsa
CIRCUIT_NAME=batch_ecdsa
SIGNALS=./scripts/batch_ecdsa_inputs.json

if [ -f "$PHASE1" ]; then
    echo "Found Phase 1 ptau file $PHASE1"
    # TODO check file hash matches https://github.com/iden3/snarkjs#7-prepare-phase-2
    # TODO verify ptau file https://github.com/iden3/snarkjs#8-verify-the-final-ptau
else
    echo "Phase 1 ptau file not found: $PHASE1"
    graceful_exit 1
fi

if [ ! -d "$BUILD_DIR" ]; then
    echo "No build directory found. Creating build directory..."
    mkdir -p "$BUILD_DIR"
fi


MSG="COMPILING CIRCUIT"
# add `--sym` to generate circuit.sym (a symbols file required for debugging and printing the constraint system in an annotated mode)
# what is --O1? Level of simplification done for the constraints (0, 1, 2)
# In practice, one may still need to use --O1 because the further --O2 optimization takes significantly longer on large circuits (for reasons that aren’t totally clear).
#execute circom "$CIRCUITS_DIR"/"$CIRCUIT_NAME".circom --O1 --c --r1cs --output "$BUILD_DIR"
execute circom "$CIRCUITS_DIR"/"$CIRCUIT_NAME".circom --O1 --wasm --r1cs --output "$BUILD_DIR"

MSG="GENERATING WITNESS FOR SAMPLE INPUT"
execute node "$BUILD_DIR"/"$CIRCUIT_NAME"_js/generate_witness.js "$BUILD_DIR"/"$CIRCUIT_NAME"_js/"$CIRCUIT_NAME".wasm "$SIGNALS" "$BUILD_DIR"/witness.wtns

# MSG="COMPILING C++ WITNESS GENERATION CODE"
# cd "$BUILD_DIR"/"$CIRCUIT_NAME"_cpp
# execute make

# MSG="GENERATING WITNESS"
# execute ./"$CIRCUIT_NAME" ../../../"$SIGNALS" ../witness.wtns
# cd -

execute npx snarkjs wtns check "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$BUILD_DIR"/witness.wtns


