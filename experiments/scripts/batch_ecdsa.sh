#!/bin/bash

# Ran this script on an r7a.8xl (256GB RAM & 32 4th generation AMD EPYC processors)
# after running the machine_initialization script.

# Benchmarks:
#  1. compiling circuit:
#    - time: 23m (c++)
#    - max cpu: 23%
#    - max mem: 16%
#    - non-linear constraints: 58_083_270
#    - linear constraints: 3_419_228
#    - public inputs: 512
#    - private inputs: 2560
#    - public outputs: 1
#    - wires: 61130056
#    - labels: 83118319
#  2. generating witness: 13m
#  3. checking witness: 13m
#  4. generating zkey 0:
#    - time: 16h
#    - max cpu: 36%
#    - max mem: 79%
#  5. contributing to phase 2 ceremony:
#    - time: 19m
#    - max cpu: 95%
#    - max mem: 1%
#  6. verifying final zkey: HERE
#    - time: 15h
#    - max cpu: 84%
#    - max mem: 56%
#  7. generating proof:
#    - time: 1m
#    - max cpu: 47%
#    - max mem: 24%

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
function execute {
    ERR_MSG="ERROR $MSG"
    printf "\n================ $MSG ================\n"
    date
    \time --quiet "${@:1}"
}

############################################
################## SETUP ###################
############################################

# Circuit compilation commands were originally taken from https://hackmd.io/@yisun/BkT0RS87q

CIRCUITS_DIR=./circuits
PHASE1=./powersOfTau28_hez_final_26.ptau
BUILD_DIR=./build/batch_ecdsa
CIRCUIT_NAME=batch_ecdsa
SIGNALS=./scripts/batch_ecdsa_input_prep/input_128.json

# Format for the `time` command (see `man time` for more details).
export TIME="STATS: time ([H:]M:S) %E ; mem %KKb ; cpu %P"

# For the non-patched node version. snarkjs requires lots of memory.
export NODE_OPTIONS="--max-old-space-size=200000"

# For the patched node version.
NODE_CLI_OPTIONS="--max-old-space-size=2048000 --initial-old-space-size=2048000 --no-global-gc-scheduling --no-incremental-marking --max-semi-space-size=1024 --initial-heap-size=2048000 --expose-gc"

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

if [[ -z "$PATCHED_NODE_PATH" ]]; then
    echo "PATCHED_NODE_PATH env var not set. Must be set for optimized phase 2 trusted setup."
    graceful_exit 1
fi

if [[ -z "$SNARKJS_PATH" ]]; then
    echo "SNARKJS_PATH env var not set. Must be set for optimized trusted setup."
    graceful_exit 1
fi

if [[ -z "$RAPIDSNARK_PATH" ]]; then
    echo "RAPIDSNARK_PATH env var not set. Must be set for optimized proof generation."
    graceful_exit 1
fi

############################################
################ COMMANDS ##################
############################################

MSG="COMPILING CIRCUIT"
# --O1 optimization only removes “equals” constraints but does not optimize out “linear” constraints.
# the further --O2 optimization takes significantly longer on large circuits (for reasons that aren’t totally clear)
# time: 23m with c++
#  non-linear constraints: 58_083_270
#  linear constraints: 3_419_228
#  public inputs: 512
#  private inputs: 2560
#  public outputs: 1
#  wires: 61130056
#  labels: 83118319
execute circom "$CIRCUITS_DIR"/"$CIRCUIT_NAME".circom --O1 --r1cs --sym --c --output "$BUILD_DIR" -l ./node_modules -l ./git_modules

MSG="COMPILING C++ WITNESS GENERATION CODE"
cd "$BUILD_DIR"/"$CIRCUIT_NAME"_cpp
# time: 1m
execute make

MSG="GENERATING WITNESS"
# time: 13m
execute ./"$CIRCUIT_NAME" ../../../"$SIGNALS" ../witness.wtns
cd -

MSG="CHECKING WITNESS"
# took 13m
execute snarkjs wtns check "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$BUILD_DIR"/witness.wtns

MSG="GENERATING ZKEY 0"
# time: 16h
execute "$PATCHED_NODE_PATH" $NODE_CLI_OPTIONS "$SNARKJS_PATH" zkey new "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$PHASE1" "$BUILD_DIR"/"$CIRCUIT_NAME"_0.zkey

MSG="CONTRIBUTING TO PHASE 2 CEREMONY"
# time: 19m
execute snarkjs zkey contribute "$BUILD_DIR"/"$CIRCUIT_NAME"_0.zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey --name="First contributor" -e="random text for entropy"

MSG="GENERATING FINAL ZKEY"
# what is this random hex? https://github.com/iden3/snarkjs#20-apply-a-random-beacon
# execute npx snarkjs zkey beacon "$BUILD_DIR"/"$CIRCUIT_NAME"_1.zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey 0102030405060708090a0b0c0d0e0f101112231415161718221a1b1c1d1e1f 10 -n="Final Beacon phase2"

MSG="CONVERTING WITNESS TO JSON"
# took 1.5 hrs then I killed it
execute snarkjs wej "$BUILD_DIR"/witness.wtns "$BUILD_DIR"/witness.json

MSG="VERIFYING FINAL ZKEY"
# time: 15h
execute npx snarkjs zkey verify "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$PHASE1" "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey

MSG="EXPORTING VKEY"
# time: <1s
execute "$PATCHED_NODE_PATH" "$SNARKJS_PATH" zkey export verificationkey "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_vkey.json

MSG="GENERATING PROOF FOR SAMPLE INPUT"
# time: 1m
execute "$RAPIDSNARK_PATH" "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey "$BUILD_DIR"/witness.wtns "$BUILD_DIR"/proof.json "$BUILD_DIR"/public.json

MSG="VERIFYING PROOF FOR SAMPLE INPUT"
execute "$PATCHED_NODE_PATH" "$SNARKJS_PATH" groth16 verify "$BUILD_DIR"/"$CIRCUIT_NAME"_vkey.json "$BUILD_DIR"/public.json "$BUILD_DIR"/proof.json
