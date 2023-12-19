#!/bin/bash

############################################
########### ERROR HANDLING #################
############################################

# http://stackoverflow.com/questions/35800082/ddg#35800451
set -eE

# call like `graceful_exit <exit_code>`
function graceful_exit {
    echo -e "\n####### EXITING... #######\n"
    DEFAULT_EXIT_CODE=0
    exit ${1:-$DEFAULT_EXIT_CODE} # use first param or default to 0
}

# Print line number & message of error and exit gracefully
# call like `err_report $LINENO $ERR_MSG`
function err_report {
    ret=$? # previous command exit value
    echo -e "\n####### A COMMAND FAILED ON LINE $1 #######\n"
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

# copied from https://github.com/sethhrbek/heyanoun/blob/c043243493710109cb1d0f47daaf1015e908b1b4/circuits/scripts/build.sh

CIRCUITS_DIR=./circuits
PHASE1=./powersOfTau28_hez_final_22.ptau
BUILD_DIR=./build/ecdsa_verification
CIRCUIT_NAME=ecdsa_verification

if [ -f "$PHASE1" ]; then
    echo "Found Phase 1 ptau file $PHASE1"
else
    echo "Phase 1 ptau file not found: $PHASE1\nExiting..."
    exit 1
fi

if [ ! -d "$BUILD_DIR" ]; then
    echo "No build directory found. Creating build directory..."
    mkdir -p "$BUILD_DIR"
fi

ERR_MSG="Cannot compile circuit"
echo "****COMPILING CIRCUIT****"
start=`date +%s`
circom "$CIRCUITS_DIR"/"$CIRCUIT_NAME".circom --r1cs --wasm --sym --c --wat --output "$BUILD_DIR" -l ./node_modules
end=`date +%s`
echo "DONE ($((end-start))s)"

ERR_MSG="Cannot generate zkey 0"
echo "****GENERATING ZKEY 0****"
start=`date +%s`
npx snarkjs groth16 setup "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$PHASE1" "$BUILD_DIR"/"$CIRCUIT_NAME"_0.zkey
end=`date +%s`
echo "DONE ($((end-start))s)"

ERR_MSG="Cannot contribute to phase 2"
echo "****CONTRIBUTE TO PHASE 2 CEREMONY****"
start=`date +%s`
npx snarkjs zkey contribute "$BUILD_DIR"/"$CIRCUIT_NAME"_0.zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_1.zkey --name="First contributor" -e="random text for entropy"
end=`date +%s`
echo "DONE ($((end-start))s)"

ERR_MSG="Cannot generate final zkey"
echo "****GENERATING FINAL ZKEY****"
start=`date +%s`
NODE_OPTIONS="--max-old-space-size=56000" npx snarkjs zkey beacon "$BUILD_DIR"/"$CIRCUIT_NAME"_1.zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey 12FE2EC467BD428DD0E966A6287DE2AF8DE09C2C5C0AD902B2C666B0895ABB75 10 -n="Final Beacon phase2"
end=`date +%s`
echo "DONE ($((end-start))s)"


ERR_MSG="Cannot export vkey"
echo "****EXPORTING VKEY****"
start=`date +%s`
npx snarkjs zkey export verificationkey "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_vkey.json -v
end=`date +%s`
echo "DONE ($((end-start))s)"
