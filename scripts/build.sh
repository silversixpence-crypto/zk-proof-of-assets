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
############# INSTALLATION #################
############################################

# Circuit compilation commands were originally from 0xPARC/circom-ecdsa
# Time command with backslash prefix: https://unix.stackexchange.com/questions/497094/time-not-accepting-arguments

CIRCUITS_DIR=./circuits
PHASE1=./powersOfTau28_hez_final_22.ptau
BUILD_DIR=./build/ecdsa_verification
CIRCUIT_NAME=ecdsa_verification
SIGNALS=./scripts/input.json

# Format for the `time` command (see `man time` for more details).
export TIME="STATS: time ([H:]M:S) %E ; mem %KKb ; cpu %P"

# snarkjs requires lots of memory.
export NODE_OPTIONS="--max-old-space-size=200000"

if [ -f "$PHASE1" ]; then
    echo "Found Phase 1 ptau file $PHASE1"
else
    echo "Phase 1 ptau file not found: $PHASE1"
    graceful_exit 1
fi

if [ ! -d "$BUILD_DIR" ]; then
    echo "No build directory found. Creating build directory..."
    mkdir -p "$BUILD_DIR"
fi

WORDS="COMPILING CIRCUIT"
ERR_MSG="ERROR $WORDS"
printf "\n================ $WORDS ================\n"
# TODO we don't need --c & --wasm (we should select 1 that we will use to generate the witness)
# TODO what is --wat?
\time --quiet circom "$CIRCUITS_DIR"/"$CIRCUIT_NAME".circom --r1cs --wasm --sym --c --wat --output "$BUILD_DIR" -l ./node_modules

WORDS="GENERATING WITNESS FOR SAMPLE INPUT"
ERR_MSG="ERROR $WORDS"
printf "\n================ $WORDS ================\n"
\time --quiet node "$BUILD_DIR"/"$CIRCUIT_NAME"_js/generate_witness.js "$BUILD_DIR"/"$CIRCUIT_NAME"_js/"$CIRCUIT_NAME".wasm "$SIGNALS" "$BUILD_DIR"/witness.wtns

WORDS="GENERATING ZKEY 0"
ERR_MSG="ERROR $WORDS"
printf "\n================ $WORDS ================\n"
\time --quiet npx snarkjs groth16 setup "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$PHASE1" "$BUILD_DIR"/"$CIRCUIT_NAME"_0.zkey

WORDS="CONTRIBUTING TO PHASE 2 CEREMONY"
ERR_MSG="ERROR $WORDS"
printf "\n================ $WORDS ================\n"
\time --quiet npx snarkjs zkey contribute "$BUILD_DIR"/"$CIRCUIT_NAME"_0.zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_1.zkey --name="First contributor" -e="random text for entropy"

WORDS="GENERATING FINAL ZKEY"
ERR_MSG="ERROR $WORDS"
printf "\n================ $WORDS ================\n"
# TODO what is this random hex?
\time --quiet npx snarkjs zkey beacon "$BUILD_DIR"/"$CIRCUIT_NAME"_1.zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey 12FE2EC467BD428DD0E966A6287DE2AF8DE09C2C5C0AD902B2C666B0895ABB75 10 -n="Final Beacon phase2"

WORDS="VERIFYING FINAL ZKEY"
ERR_MSG="ERROR $WORDS"
printf "\n================ $WORDS ================\n"
\time --quiet npx snarkjs zkey verify "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$PHASE1" "$BUILD_DIR"/"$CIRCUIT_NAME".zkey

WORDS="EXPORTING VKEY"
ERR_MSG="ERROR $WORDS"
printf "\n================ $WORDS ================\n"
\time --quiet npx snarkjs zkey export verificationkey "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_vkey.json -v

WORDS="GENERATING PROOF FOR SAMPLE INPUT"
ERR_MSG="ERROR $WORDS"
printf "\n================ $WORDS ================\n"
\time --quiet npx snarkjs groth16 prove "$BUILD_DIR"/"$CIRCUIT_NAME".zkey "$BUILD_DIR"/witness.wtns "$BUILD_DIR"/proof.json "$BUILD_DIR"/public.json

WORDS="VERIFYING PROOF FOR SAMPLE INPUT"
ERR_MSG="ERROR $WORDS"
printf "\n================ $WORDS ================\n"
\time --quiet npx snarkjs groth16 verify "$BUILD_DIR"/vkey.json "$BUILD_DIR"/public.json "$BUILD_DIR"/proof.json
