#!/usr/bin/env bash

# TODO change variable names to lower case, keep constants upper

############################################
################### INIT ###################
############################################

############################################
# Imports

# Get the path to the directory this script is in.
G16_SETUP_PATH="$(realpath "${BASH_SOURCE[-1]}")"
G16_SETUP_DIRECTORY="$(dirname "$G16_SETUP_PATH")"

# Inspiration taken from
# https://stackoverflow.com/questions/12815774/importing-functions-from-a-shell-script/76241268#76241268
. "$G16_SETUP_DIRECTORY/lib/error_handling.sh"
. "$G16_SETUP_DIRECTORY/lib/cmd_executor.sh"

############################################
# Constants.

PROJECT_ROOT_DIR="$G16_SETUP_DIRECTORY"/..
SNARKJS_CLI="$PROJECT_ROOT_DIR"/node_modules/snarkjs/cli.js
SNARKJS_FILE=$(basename $SNARKJS_CLI)

if [[ ! -f "$SNARKJS_CLI" ]]; then
    echo "ERROR: snarkjs not present in node_modules. Run 'pnpm i'."
    exit 1
fi

############################################
################## SETUP ###################
############################################

ERR_MSG="Most likely a bug in the shell script"

print_usage() {
    printf "
Groth16 setup for circom circuits.

USAGE:
    ./g16_setup.sh [FLAGS] [OPTIONS] <circuit_path>

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

    -q               Quick commands only. This skips proving & verification key generation.
                     Useful for testing when you only want to do compilation & witness generation.

    -r               Apply random beacon to get the final proving key (zkey)

    -v               Print commands that are run (set -x)

    -h               Help

OPTIONS:

    -B <PATH>        Build directory, where all the build artifacts are placed
                     Default is '<repo_root_dir>/build'

    -n <PATH>        Path to the patched node binary (needed for '-b')
                     Can also be set with the env var PATCHED_NODE_PATH

    -t <PATH>        Powers of tau (ptau) file path
                     Can be downloaded from here: https://github.com/iden3/snarkjs#7-prepare-phase-2
                     This is required unless you provide a pre-generated zkey (see '-Z')
                     If '-t' & '-Z' are set then '-Z' is preferred

    -Z <PATH>        Path to an already-generated proving key (zkey)
                     This will skip the lengthy zkey generation

ARGS:

    <circuit_path>   Path to a the circom circuit to be compiled & have key generation done for
"
}

if [ "$#" -lt 2 ]; then
    echo "ERROR: Not enough arguments"
    print_usage
    exit 1
fi

############################################
# Required args.

CIRCUIT_PATH="${@: -1}"

if [[ ! -f "$CIRCUIT_PATH" ]]; then
    echo "ERROR: <circuit_path> '$CIRCUIT_PATH' does not point to a file."
    print_usage
    exit 1
fi

# https://stackoverflow.com/questions/965053/extract-filename-and-extension-in-bash
CIRCUIT_FILE=$(basename $CIRCUIT_PATH)
CIRCUIT_NAME="${CIRCUIT_FILE%.*}"

if [[ "${CIRCUIT_PATH##*.}" != "circom" ]] || [[ ! -f "$CIRCUIT_PATH" ]]; then
    echo "ERROR: <circuit_path> '$CIRCUIT_PATH' does not point to an existing circom file."
    print_usage
    exit 1
fi

############################################
# Parse flags & optional args.

BEACON=false
BIG_CIRCUITS=false
BUILD_DIR="$PROJECT_ROOT_DIR"/build/
COMPILE_FLAGS="--wasm"
QUICK=false
SKIP_ZKEY_GEN=false
VERBOSE=false

# https://stackoverflow.com/questions/7069682/how-to-get-arguments-with-flags-in-bash#21128172
while getopts 'bB:hn:qr:t:vZ:' flag; do
    case "${flag}" in
    b)
        BIG_CIRCUITS=true
        COMPILE_FLAGS="--O1 --c"
        ;;
    B) BUILD_DIR="${OPTARG}" ;;
    h)
        print_usage
        exit 1
        ;;
    n) PATCHED_NODE_PATH="${OPTARG}" ;;
    q) QUICK=true ;;
    r) BEACON=true ;;
    t) PTAU_PATH="${OPTARG}" ;;
    v) VERBOSE=true ;;
    Z)
        SKIP_ZKEY_GEN=true
        ZKEY_PATH="${OPTARG}"
        ;;
    *)
        print_usage
        exit 1
        ;;
    esac
done

############################################

if $VERBOSE; then
    # print commands before executing
    set -x
fi

############################################
# Make sure build directory exists.

if [[ ! -d "$BUILD_DIR" ]]; then
    echo "Creating build directory $BUILD_DIR"
    mkdir -p "$BUILD_DIR"
fi

############################################
# Setup for big circuits.

if $BIG_CIRCUITS; then
    if [[ -z "$PATCHED_NODE_PATH" ]]; then
        echo "ERROR: Path to patched node binary not set. This must be set if using '-b'."
        print_usage
        exit 1
    fi

    PATCHED_NODE_FILE=$(basename $PATCHED_NODE_PATH)
    if [[ ! -f "$PATCHED_NODE_PATH" ]] || [[ $PATCHED_NODE_FILE != "node" ]]; then
        echo "ERROR: $PATCHED_NODE_PATH must point to a file with name 'node'"
        exit 1
    fi
fi

############################################
# Verify any provided zkey.

if $SKIP_ZKEY_GEN; then
    if [[ -z "$ZKEY_PATH" ]]; then
        echo "ERROR: Path to zkey not set, but -Z option was given."
        print_usage
        exit 1
    fi

    if [[ "${ZKEY_PATH##*.}" != "zkey" ]] || [[ ! -f "$ZKEY_PATH" ]]; then
        echo "ERROR: <zkey_path> '$ZKEY_PATH' does not point to an existing zkey file."
        print_usage
        exit 1
    fi
else
    if [[ "${PTAU_PATH##*.}" != "ptau" ]] || [[ ! -f "$PTAU_PATH" ]]; then
        echo "ERROR: <ptau_path> '$PTAU_PATH' does not point to an existing ptau file. You must provide a ptau file OR zkey file."
        print_usage
        exit 1
        # elif
        # TODO check file hash matches https://github.com/iden3/snarkjs#7-prepare-phase-2
        # TODO verify ptau file https://github.com/iden3/snarkjs#8-verify-the-final-ptau
    fi
fi

############################################

# Reset error message.
ERR_MSG="UNKNOWN"

# NOTE the script seems to work without these set.
NODE_CLI_OPTIONS="--max-old-space-size=2048000 --initial-old-space-size=2048000 --no-global-gc-scheduling --no-incremental-marking --max-semi-space-size=1024 --initial-heap-size=2048000 --expose-gc"

############################################
################ COMMANDS ##################
############################################

# Commands were originally from 0xPARC/circom-ecdsa & https://hackmd.io/V-7Aal05Tiy-ozmzTGBYPA

MSG="COMPILING CIRCUIT"
# sym: generates circuit.sym (a symbols file required for debugging and printing the constraint system in an annotated mode).
#
# --O1 optimization only removes “equals” constraints but does not optimize out “linear” constraints.
# the further --O2 optimization takes significantly longer on large circuits (for reasons that aren’t totally clear)
execute circom "$CIRCUIT_PATH" --r1cs $COMPILE_FLAGS --sym --output "$BUILD_DIR" -l ./node_modules -l ./git_modules

if $BIG_CIRCUITS; then
    MSG="COMPILING C++ WITNESS GENERATION CODE"
    cd "$BUILD_DIR"/"$CIRCUIT_NAME"_cpp
    execute make
    cd -
fi

if $QUICK; then
    printf "\n================ DONE, SKIPPING ZKEY & VKEY GENERATION ================"
    exit 0
fi

if ! $SKIP_ZKEY_GEN; then
    if $BIG_CIRCUITS; then
        MSG="GENERATING ZKEY FOR CIRCUIT USING PATCHED NODE"
        execute "$PATCHED_NODE_PATH" $NODE_CLI_OPTIONS "$SNARKJS_CLI" zkey new "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$PTAU_PATH" "$BUILD_DIR"/"$CIRCUIT_NAME"_0.zkey
    else
        MSG="GENERATING ZKEY FOR CIRCUIT"
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

    ZKEY_PATH="$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey
fi

MSG="EXPORTING VKEY"
if $BIG_CIRCUITS; then
    execute "$PATCHED_NODE_PATH" "$SNARKJS_CLI" zkey export verificationkey "$ZKEY_PATH" "$BUILD_DIR"/"$CIRCUIT_NAME"_vkey.json
else
    execute npx snarkjs zkey export verificationkey "$ZKEY_PATH" "$BUILD_DIR"/"$CIRCUIT_NAME"_vkey.json -v
fi

printf "\n================ DONE G16 SETUP ================\n"
