#!/usr/bin/env bash

# Get the path to the directory this script is in.
G16_SETUP_PATH="$(realpath "${BASH_SOURCE[-1]}")"
G16_SETUP_DIRECTORY="$(dirname "$G16_SETUP_PATH")"

. "$G16_SETUP_DIRECTORY/error_handling.sh"
. "$G16_SETUP_DIRECTORY/cmd_executor.sh"

############################################
################## SETUP ###################
############################################

# https://stackoverflow.com/questions/7069682/how-to-get-arguments-with-flags-in-bash#21128172

print_usage() {
    printf "
Groth16 setup for circom circuits.

USAGE:
    ./g16_setup.sh [FLAGS] [OPTIONS] <circuit_path> <ptau_file>

DESCRIPTION:
    This script does the following:
    1. Compile the circom circuit at <circuit_path>
    2. Generate the groth16 proving key (.zkey) for the circuit (this will take long for large circuits)
    3. Generate the groth16 verification key (.vkey) for the circuit

FLAGS:

    -b               Big circuits. Perform optimizations for large circuits:
                     - Use C++ circom witness generation (default is wasm)
                     - Do not let circom try to optimize linear constraints (--02) which takes significantly longer on large circuits
                     - Use patched version of node (path to this must be set with '-n'), see these for more info
                       https://hackmd.io/V-7Aal05Tiy-ozmzTGBYPA#Install-patched-node
                       https://github.com/hermeznetwork/phase2ceremony_4/blob/main/VERIFY.md#adding-swap-and-tweeking-the-os-to-accept-high-amount-of-memory
                     - Use v0.3.59 of snarkjs (path to this must be set with '-s'), see here for more info
                       https://hackmd.io/V-7Aal05Tiy-ozmzTGBYPA#Install-snarkjs-from-source

    -r               Apply random beacon to get the final proving key (zkey)

    -z               Verify the final proving key (zkey)
                     WARN: this takes long for large circuits

    -v               Print commands that are run (set -x)

    -h               Help

OPTIONS:

    -B <PATH>        Build directory, where all the build artifacts are placed
                     Default is '<repo_root_dir>/build'

    -n <PATH>        Path to the patched node binary (needed for '-b')
                     Can also be set with the env var PATCHED_NODE_PATH

    -s <PATH>        Path to the v0.3.59 snarkjs cli (needed for '-b')
                     Can also be set with the env var SNARKJS_PATH

ARGS:

    <circuit_path>   Path to a the circom circuit to be compiled & have key generation done for

    <ptau_path>      Path to the powers of tau file.
                     Can be downloaded from here: https://github.com/iden3/snarkjs#7-prepare-phase-2
"
}

COMPILE_FLAGS="--wasm"
BIG_CIRCUITS=false
BEACON=false
VERIFY_ZKEY=false
VERBOSE=false

# https://stackoverflow.com/questions/11054939/how-to-get-the-second-last-argument-from-shell-script#11055032
CIRCUIT_PATH="${@:(-2):1}"
PTAU_PATH="${@: -1}"

BUILD_DIR=$G16_SETUP_DIRECTORY/../build/

while getopts 'vhbrzn:s:B:' flag; do
    case "${flag}" in
        b)
            BIG_CIRCUITS=true
            COMPILE_FLAGS="--O1 --c"
            ;;
        r) BEACON=true ;;
        z) VERIFY_ZKEY=true ;;
        n) PATCHED_NODE_PATH="${OPTARG}" ;;
        s) SNARKJS_PATH="${OPTARG}" ;;
        B) BUILD_DIR="${OPTARG}" ;;
        v) VERBOSE=true ;;
        h)
            print_usage
            exit 1
            ;;
        *)
            print_usage
            exit 1
            ;;
    esac
done

if $VERBOSE; then
    # print commands before executing
    set -x
fi

if [[ ! -f "$CIRCUIT_PATH" ]]; then
    echo "<circuit_path> '$CIRCUIT_PATH' does not point to a file."
    print_usage
    exit 1
fi

# https://stackoverflow.com/questions/965053/extract-filename-and-extension-in-bash
CIRCUIT_FILE=$(basename $CIRCUIT_PATH)
CIRCUIT_NAME="${CIRCUIT_FILE%.*}"

if [[ "${CIRCUIT_PATH##*.}" != "circom" ]] || [[ ! -f "$CIRCUIT_PATH" ]]; then
    echo "<circuit_path> '$CIRCUIT_PATH' does not point to an existing circom file."
    print_usage
    exit 1
fi

if [[ ! -d "$BUILD_DIR" ]]; then
    echo "Creating build directory $BUILD_DIR"
    mkdir -p "$BUILD_DIR"
fi

if [[ "${PTAU_PATH##*.}" != "ptau" ]] || [[ ! -f "$PTAU_PATH" ]]; then
    echo "<ptau_path> '$PTAU_PATH' does not point to an existing ptau file."
    print_usage
    exit 1
# elif
# TODO check file hash matches https://github.com/iden3/snarkjs#7-prepare-phase-2
# TODO verify ptau file https://github.com/iden3/snarkjs#8-verify-the-final-ptau
fi

if $BIG_CIRCUITS; then
    # TODO also check that these are files with the correct name etc

    if [[ -z "$PATCHED_NODE_PATH" ]]; then
        echo "Path to patched node binary not set. This must be set if using '-b'."
        print_usage
        exit 1
    fi

    if [[ -z "$SNARKJS_PATH" ]]; then
        echo "Path to v0.3.59  snarkjs not set. This must be set if using '-b'."
        print_usage
        exit 1
    fi
fi

############################################
################ COMMANDS ##################
############################################

# Commands were originally from 0xPARC/circom-ecdsa & https://hackmd.io/V-7Aal05Tiy-ozmzTGBYPA

# TODO add more info to the messaging, such as "generating proof using rapidsnark"

MSG="COMPILING CIRCUIT"
# TODO what is --wat?
#
# sym: generates circuit.sym (a symbols file required for debugging and printing the constraint system in an annotated mode).
#
# --O1 optimization only removes “equals” constraints but does not optimize out “linear” constraints.
# the further --O2 optimization takes significantly longer on large circuits (for reasons that aren’t totally clear)
execute circom "$CIRCUIT_PATH" --r1cs $COMPILE_FLAGS --sym --wat --output "$BUILD_DIR" -l ./node_modules

if $BIG_CIRCUITS; then
    MSG="COMPILING C++ WITNESS GENERATION CODE"
    cd "$BUILD_DIR"/"$CIRCUIT_NAME"_cpp
    execute make
    cd -
fi

MSG="GENERATING ZKEY 0"
if $BIG_CIRCUITS; then
    execute "$PATCHED_NODE_PATH" $NODE_CLI_OPTIONS "$SNARKJS_PATH" zkey new "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$PTAU_PATH" "$BUILD_DIR"/"$CIRCUIT_NAME"_0.zkey
else
    execute npx snarkjs groth16 setup "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$PTAU_PATH" "$BUILD_DIR"/"$CIRCUIT_NAME"_0.zkey
fi

MSG="CONTRIBUTING TO PHASE 2 CEREMONY"
if $BEACON; then
    SUFFIX="1"
else
    SUFFIX="final"
fi
# TODO allow cli to give random text for entropy
execute npx snarkjs zkey contribute "$BUILD_DIR"/"$CIRCUIT_NAME"_0.zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_"$SUFFIX".zkey --name="First contributor" -e="random text for entropy"

# TODO allow cli to give randomness
if $BEACON; then
    MSG="GENERATING FINAL ZKEY USING RANDOM BEACON"
    # what is this random hex? https://github.com/iden3/snarkjs#20-apply-a-random-beacon
    execute npx snarkjs zkey beacon "$BUILD_DIR"/"$CIRCUIT_NAME"_"$SUFFIX".zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey 0102030405060708090a0b0c0d0e0f101112231415161718221a1b1c1d1e1f 10 -n="Final Beacon phase2"
fi

MSG="VERIFYING FINAL ZKEY"
if $VERIFY_ZKEY; then
    execute npx snarkjs zkey verify "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$PTAU_PATH" "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey
fi

# TODO there is a fast version of this using patched node
MSG="EXPORTING VKEY"
if $BIG_CIRCUITS; then
    execute "$PATCHED_NODE_PATH" "$SNARKJS_PATH" zkey export verificationkey "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_vkey.json
else
    execute npx snarkjs zkey export verificationkey "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey "$BUILD_DIR"/"$CIRCUIT_NAME"_vkey.json -v
fi
