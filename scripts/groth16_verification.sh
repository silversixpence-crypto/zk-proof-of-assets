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

function execute {
    date
    ERR_MSG="ERROR $MSG"
    printf "\n================ $MSG ================\n"
    \time --quiet "${@:1}"
}

############################################
################ COMMANDS ##################
############################################

# Circuit compilation commands were originally from https://github.com/yi-sun/circom-pairing/blob/107c316223a08ac577522c54edd81f0fc4c03130/scripts/dev/build_dev.sh
# Time command with backslash prefix: https://unix.stackexchange.com/questions/497094/time-not-accepting-arguments

CIRCUITS_DIR=./circuits
PHASE1=./powersOfTau28_hez_final_25.ptau
BUILD_DIR=./build/groth16_verification
CIRCUIT_NAME=groth16_verification
SIGNALS=./scripts/groth16_verification_inputs.json

# Format for the `time` command (see `man time` for more details).
export TIME="STATS: time ([H:]M:S) %E ; mem %KKb ; cpu %P"

# snarkjs requires lots of memory.
export NODE_OPTIONS="--max-old-space-size=200000"

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
# what is --O2? Level of simplification done for the constraints (0, 1, 2)
# sym: generates circuit.sym (a symbols file required for debugging and printing the constraint system in an annotated mode).
# takes about 50 min
# constraints: 32_451_250
execute circom "$CIRCUITS_DIR"/"$CIRCUIT_NAME".circom --O2 --r1cs --wasm --sym --output "$BUILD_DIR" -l ./node_modules

MSG="PRINTING CIRCUIT INFO"
# took 2hrs to use 128GB of ram, then I killed it
# execute npx snarkjs r1cs info "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs

# echo "COMPILING C++ WITNESS GENERATION CODE"
# cd "$BUILD_DIR"/"$CIRCUIT_NAME"_cpp
# make

# MSG="VERIFYING WITNESS"
# execute ./"$CIRCUIT_NAME" ../../../scripts/"$SIGNALS" ../witness.wtns

# cd ..
# npx snarkjs wej witness.wtns witness.json
# cd ../..

MSG="GENERATING WITNESS FOR SAMPLE INPUT"
# took 20 min
#execute node "$BUILD_DIR"/"$CIRCUIT_NAME"_js/generate_witness.js "$BUILD_DIR"/"$CIRCUIT_NAME"_js/"$CIRCUIT_NAME".wasm "$SIGNALS" "$BUILD_DIR"/witness.wtns

MSG="CHECKING WITNESS"
# took 12 min
#execute npx snarkjs wtns check "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$BUILD_DIR"/witness.wtns

MSG="GENERATING ZKEY 0"
# fails after 20 min, then I set `sysctl -w vm.max_map_count=655300`
# https://stackoverflow.com/questions/38558989/node-js-heap-out-of-memory/59923848#59923848
# takes 27 hours & used 167GB mem
#execute npx snarkjs groth16 setup "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$PHASE1" "$BUILD_DIR"/"$CIRCUIT_NAME"_0.zkey

MSG="CONTRIBUTING TO PHASE 2 CEREMONY"
execute npx snarkjs zkey contribute "$BUILD_DIR"/"$CIRCUIT_NAME"_0.zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_1.zkey --name="First contributor" -e="random text for entropy"

# Proving key
MSG="GENERATING FINAL ZKEY"
# what is this random hex? https://github.com/iden3/snarkjs#20-apply-a-random-beacon
execute npx snarkjs zkey beacon "$BUILD_DIR"/"$CIRCUIT_NAME"_1.zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey 0102030405060708090a0b0c0d0e0f101112231415161718221a1b1c1d1e1f 10 -n="Final Beacon phase2"

MSG="VERIFYING FINAL ZKEY"
execute npx snarkjs zkey verify -verbose "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$PHASE1" "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey

# Verifying key
MSG="EXPORTING VKEY"
execute npx snarkjs zkey export verificationkey "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_vkey.json -v

MSG="GENERATING PROOF FOR SAMPLE INPUT"
execute npx snarkjs groth16 prove "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey "$BUILD_DIR"/witness.wtns "$BUILD_DIR"/proof.json "$BUILD_DIR"/public.json

MSG="VERIFYING PROOF FOR SAMPLE INPUT"
execute npx snarkjs groth16 verify "$BUILD_DIR"/"$CIRCUIT_NAME"_vkey.json "$BUILD_DIR"/public.json "$BUILD_DIR"/proof.json
