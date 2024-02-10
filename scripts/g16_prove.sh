#!/usr/bin/env bash

# This script does the following:
# 1. Compile the circom circuit at $CIRCUITS_DIR/$CIRCUIT_NAME
# 2. Generate the proving key for groth16 (.zkey)

# Get the path to the directory this script is in.
G16_PROVE_PATH="$(realpath "${BASH_SOURCE[-1]}")"
G16_PROVE_DIRECTORY="$(dirname "$G16_PROVE_PATH")"

. "$G16_PROVE_DIRECTORY/error_handling.sh"
. "$G16_PROVE_DIRECTORY/cmd_executor.sh"

############################################
################## SETUP ###################
############################################

# https://stackoverflow.com/questions/7069682/how-to-get-arguments-with-flags-in-bash#21128172

print_usage() {
    printf "
Groth16 proof generation for circom circuits.

USAGE:
    ./g16_prove.sh [FLAGS] [OPTIONS] <circuit_path> <signals_path>

DESCRIPTION:
    It is assumed that the following are present in the build directory:
    - The circom witness generation files
    - The proving key (.zkey)

    This script does the following:
    1. Generate witness for <circuit_path> & <signals_path>
    2. Generate the groth16 proof for witness

FLAGS:

    -b               Big circuits. Perform optimizations for large circuits:
                     - Use C++ circom witness generation (default is wasm)
                     - Use patched version of node (path to this must be set with '-n'), see these for more info
                       https://hackmd.io/V-7Aal05Tiy-ozmzTGBYPA#Install-patched-node
                       https://github.com/hermeznetwork/phase2ceremony_4/blob/main/VERIFY.md#adding-swap-and-tweeking-the-os-to-accept-high-amount-of-memory
                     - Use rapidsnark (path to this must be set with '-r'), see this for more info
                       https://hackmd.io/V-7Aal05Tiy-ozmzTGBYPA#Install-rapidsnark-from-source

    -z               Verify the final proving key (zkey)
                     WARN: this takes long for large circuits

    -w               Verify the witness

    -v               Print commands that are run (set -x)

    -h               Help

OPTIONS:

    -B <PATH>        Build directory, where all the build artifacts are placed
                     Default is '<repo_root_dir>/build'

    -n <PATH>        Path to the patched node binary (needed for '-b')
                     Can also be set with the env var PATCHED_NODE_PATH

    -r <PATH>        Path to the rapidsnark binary (needed for '-b')
                     Can also be set with the env var RAPIDSNARK_PATH

ARGS:

    <circuit_path>   Path to a the circom circuit to generate a witness for

    <signals_path>   Path to the json file containing the input signals for the circuit
"
}

BIG_CIRCUITS=false
VERIFY_ZKEY=false
VERIFY_WITNESS=false
VERBOSE=false

# https://stackoverflow.com/questions/11054939/how-to-get-the-second-last-argument-from-shell-script#11055032
CIRCUIT_PATH="${@:(-2):1}"
SIGNALS="${@: -1}"

BUILD_DIR=$G16_PROVE_DIRECTORY/../build

while getopts 'vhbzwn:r:B:' flag; do
    case "${flag}" in
    b)
        BIG_CIRCUITS=true
        COMPILE_FLAGS="--01 --c"
        ;;
    z) VERIFY_ZKEY=true ;;
    w) VERIFY_WITNESS=true ;;
    n) PATCHED_NODE_PATH="${OPTARG}" ;;
    r) RAPIDSNARK_PATH="${OPTARG}" ;;
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
    echo "<circuit_path> '$CIRCUIT_PATH' does not point to an existing  circom file."
    print_usage
    exit 1
fi

if [[ ! -d "$BUILD_DIR" ]]; then
    echo "Creating build directory $BUILD_DIR"
    mkdir -p "$BUILD_DIR"
fi

if [[ "${SIGNALS##*.}" != "json" ]] || [[ ! -f "$SIGNALS" ]]; then
    echo "<signals> '$SIGNALS' does not point to an existing json file."
    print_usage
    exit 1
fi

if $BIG_CIRCUITS; then
    # TODO check that the cpp witness generation code is available

    if [[ -z "$PATCHED_NODE_PATH" ]]; then
        echo "Path to patched node binary not set. This must be set if using '-b'."
        print_usage
        exit 1
    fi

    if [[ -z "$RAPIDSNARK_PATH" ]]; then
        echo "Path to rapidsnark binary not set. This must be set if using '-b'."
        print_usage
        exit 1
    fi

#else
# TODO check that the js witness generation code is available
fi

############################################
################ COMMANDS ##################
############################################

# Commands were originally from 0xPARC/circom-ecdsa & https://hackmd.io/V-7Aal05Tiy-ozmzTGBYPA

# TODO add more info to the messaging, such as "generating proof using rapidsnark"

MSG="VERIFYING FINAL ZKEY"
if $VERIFY_ZKEY; then
    execute npx snarkjs zkey verify "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$PTAU_PATH" "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey
fi

MSG="GENERATING WITNESS FOR SAMPLE INPUT"
if $BIG_CIRCUITS; then
    execute "$BUILD_DIR"/"$CIRCUIT_NAME"_cpp/"$CIRCUIT_NAME" "$SIGNALS" "$BUILD_DIR"/witness.wtns
else
    execute npx node "$BUILD_DIR"/"$CIRCUIT_NAME"_js/generate_witness.js "$BUILD_DIR"/"$CIRCUIT_NAME"_js/"$CIRCUIT_NAME".wasm "$SIGNALS" "$BUILD_DIR"/witness.wtns
fi

MSG="VERIFYING WITNESS"
if $VERIFY_WITNESS; then
    execute snarkjs wtns check "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$BUILD_DIR"/witness.wtns
fi

MSG="GENERATING PROOF FOR SAMPLE INPUT"
if $BIG_CIRCUITS; then
    execute "$RAPIDSNARK_PATH" "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey "$BUILD_DIR"/witness.wtns "$BUILD_DIR"/proof.json "$BUILD_DIR"/public.json
else
    execute npx snarkjs groth16 prove "$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey "$BUILD_DIR"/witness.wtns "$BUILD_DIR"/proof.json "$BUILD_DIR"/public.json
fi
