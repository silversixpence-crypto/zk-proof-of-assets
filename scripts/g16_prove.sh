#!/usr/bin/env bash

# TODO change variable names to lower case, keep constants upper

############################################
################### INIT ###################
############################################

############################################
# Imports

# Get the path to the directory this script is in.
G16_PROVE_PATH="$(realpath "${BASH_SOURCE[-1]}")"
G16_PROVE_DIRECTORY="$(dirname "$G16_PROVE_PATH")"

# Inspiration taken from
# https://stackoverflow.com/questions/12815774/importing-functions-from-a-shell-script/76241268#76241268
. "$G16_PROVE_DIRECTORY/lib/error_handling.sh"
. "$G16_PROVE_DIRECTORY/lib/cmd_executor.sh"

############################################
################## SETUP ###################
############################################

ERR_MSG="Most likely a bug in the shell script"

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

    -q               Quick commands only
                     This skips proof generation, which is useful if you only want to do witness generation

    -w               Verify the witness

    -z               Verify the final proving key (zkey)
                     You must also specify the ptau file path with '-t'
                     WARN: this takes long for large circuits

    -v               Print commands that are run (set -x)

    -h               Help

OPTIONS:

    -B <PATH>        Build directory, where all the build artifacts are placed
                     Default is '<repo_root_dir>/build'

    -n <PATH>        Path to the patched node binary (needed for '-b')
                     Can also be set with the env var PATCHED_NODE_PATH

    -p <DIR>         Proof directory, where the witness & g16 proof will be written to
                     Default is the same as the build directory

    -r <PATH>        Path to the rapidsnark binary (needed for big circuits, see '-b')
                     Can also be set with the env var RAPIDSNARK_PATH

    -t <PATH>        Powers of tau (ptau) file path (used for verifying the zkey, see '-z')

    -Z <PATH>        Path to proving key (zkey)
                     Default is '<build_dir>/<circuit_name>_final.zkey'

ARGS:

    <circuit_path>   Path to a the circom circuit to generate a witness for

    <signals_path>   Path to the json file containing the input signals for the circuit
"
}

if [ "$#" -lt 2 ]; then
    echo "ERROR: Not enough arguments"
    print_usage
    exit 1
fi

############################################
# Required args.

# https://stackoverflow.com/questions/11054939/how-to-get-the-second-last-argument-from-shell-script#11055032
CIRCUIT_PATH="${@:(-2):1}"
SIGNALS_PATH="${@: -1}"

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

if [[ "${SIGNALS_PATH##*.}" != "json" ]] || [[ ! -f "$SIGNALS_PATH" ]]; then
    echo "ERROR: <signals_path> '$SIGNALS_PATH' does not point to an existing json file."
    print_usage
    exit 1
fi

############################################
# Parse flags & optional args.

BIG_CIRCUITS=false
BUILD_DIR="$G16_PROVE_DIRECTORY"/../build
QUICK=false
VERBOSE=false
VERIFY_WITNESS=false
VERIFY_ZKEY=false
ZKEY_HAS_CUSTOM_PATH=false

# https://stackoverflow.com/questions/7069682/how-to-get-arguments-with-flags-in-bash#21128172
while getopts 'bB:hn:p:qr:t:vwzZ:' flag; do
    case "${flag}" in
    b)
        BIG_CIRCUITS=true
        COMPILE_FLAGS="--01 --c"
        ;;
    B) BUILD_DIR="${OPTARG}" ;;
    h)
        print_usage
        exit 1
        ;;
    n) PATCHED_NODE_PATH="${OPTARG}" ;;
    p) PROOF_DIR="${OPTARG}" ;;
    q) QUICK=true ;;
    r) RAPIDSNARK_PATH="${OPTARG}" ;;
    t) PTAU_PATH="${OPTARG}" ;;
    v) VERBOSE=true ;;
    w) VERIFY_WITNESS=true ;;
    z) VERIFY_ZKEY=true ;;
    Z)
        ZKEY_HAS_CUSTOM_PATH=true
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

if $VERIFY_ZKEY; then
    if [[ "${PTAU_PATH##*.}" != "ptau" ]] || [[ ! -f "$PTAU_PATH" ]]; then
        echo "ERROR: <ptau_path> '$PTAU_PATH' does not point to an existing ptau file. You must provide a ptau file if you want the zkey to be verified."
        print_usage
        exit 1
        # elif
        # TODO check file hash matches https://github.com/iden3/snarkjs#7-prepare-phase-2
        # TODO verify ptau file https://github.com/iden3/snarkjs#8-verify-the-final-ptau
    fi
fi

############################################
# Verify build directory exists.

if [[ ! -d "$BUILD_DIR" ]]; then
    echo "Build directory $BUILD_DIR does not exist"
    exit 1
fi

############################################
# Make sure proof directory exists.

if [[ -z "$PROOF_DIR" ]]; then
    echo "Proof directory not set, defaulting to build directory: $BUILD_DIR"
    PROOF_DIR="$BUILD_DIR"
fi

if [[ ! -d "$PROOF_DIR" ]]; then
    echo "Creating proof directory $PROOF_DIR"
    mkdir -p "$PROOF_DIR"
fi

############################################
# Verify custom zkey path.

if $ZKEY_HAS_CUSTOM_PATH; then
    if [[ -z $ZKEY_PATH ]]; then
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
    ZKEY_PATH="$BUILD_DIR"/"$CIRCUIT_NAME"_final.zkey
fi

############################################
# Setup for big circuits.

if $BIG_CIRCUITS; then
    if [[ -z $PATCHED_NODE_PATH ]]; then
        echo "ERROR: Path to patched node binary not set. This must be set if using '-b'."
        print_usage
        exit 1
    fi

    PATCHED_NODE_FILE=$(basename $PATCHED_NODE_PATH)
    if [[ ! -f "$PATCHED_NODE_PATH" ]] || [[ $PATCHED_NODE_FILE != "node" ]]; then
        echo "ERROR: $PATCHED_NODE_PATH must point to a file with name 'node'"
        exit 1
    fi

    if [[ -z "$RAPIDSNARK_PATH" ]]; then
        echo "ERROR: Path to rapidsnark binary not set. This must be set if using '-b'."
        print_usage
        exit 1
    fi

    RAPIDSNARK_FILE=$(basename "$RAPIDSNARK_PATH")
    if [[ ! -f "$RAPIDSNARK_PATH" ]] || [[ $RAPIDSNARK_FILE != "prover" ]]; then
        echo "ERROR: $RAPIDSNARK_PATH must point to a file with name 'prover'"
        exit 1
    fi

    EXPECTED_WTNS_GEN_PATH="$BUILD_DIR"/"$CIRCUIT_NAME"_cpp/"$CIRCUIT_NAME"
else
    EXPECTED_WTNS_GEN_PATH="$BUILD_DIR"/"$CIRCUIT_NAME"_js/generate_witness.js
fi

if [[ ! -f "$EXPECTED_WTNS_GEN_PATH" ]]; then
    echo "ERROR: The witness generation code does not exist at the expected path $EXPECTED_WTNS_GEN_PATH"
    exit 1
fi

############################################
# Reset error message.

ERR_MSG="UNKNOWN"

############################################
################ COMMANDS ##################
############################################

# Commands were originally from 0xPARC/circom-ecdsa & https://hackmd.io/V-7Aal05Tiy-ozmzTGBYPA

# TOOD we should have a better naming scheme for zkeys.
# Should include the number of signatures or input size or something
# since the zkey is specific to the circuit + parameters, not just circuit
# e.g. layer_one_128_sigs.zkey
# e.g. layer_three_1_proof.zkey

MSG="VERIFYING FINAL ZKEY"
if $VERIFY_ZKEY; then
    execute npx snarkjs zkey verify "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$PTAU_PATH" "$ZKEY_PATH"
fi

if $BIG_CIRCUITS; then
    MSG="GENERATING WITNESS USING C++ CODE"
    execute "$BUILD_DIR"/"$CIRCUIT_NAME"_cpp/"$CIRCUIT_NAME" "$SIGNALS_PATH" "$PROOF_DIR"/witness.wtns
else
    MSG="GENERATING WITNESS USING WASM CODE"
    execute npx node "$BUILD_DIR"/"$CIRCUIT_NAME"_js/generate_witness.js "$BUILD_DIR"/"$CIRCUIT_NAME"_js/"$CIRCUIT_NAME".wasm "$SIGNALS_PATH" "$PROOF_DIR"/witness.wtns
fi

if $QUICK; then
    printf "\n================ DONE, SKIPPING PROOF GENERATION ================"
    exit 0
fi

MSG="VERIFYING WITNESS"
if $VERIFY_WITNESS; then
    execute snarkjs wtns check "$BUILD_DIR"/"$CIRCUIT_NAME".r1cs "$PROOF_DIR"/witness.wtns
fi

if $BIG_CIRCUITS; then
    MSG="GENERATING PROOF USING RAPIDSNARK"
    execute "$RAPIDSNARK_PATH" "$ZKEY_PATH" "$PROOF_DIR"/witness.wtns "$PROOF_DIR"/proof.json "$PROOF_DIR"/public.json
else
    MSG="GENERATING PROOF USING SNARKJS"
    execute npx snarkjs groth16 prove "$ZKEY_PATH" "$PROOF_DIR"/witness.wtns "$PROOF_DIR"/proof.json "$PROOF_DIR"/public.json
fi

MSG="VERIFYING PROOF"
execute npx snarkjs groth16 verify "$BUILD_DIR"/"$CIRCUIT_NAME"_vkey.json "$PROOF_DIR"/public.json "$PROOF_DIR"/proof.json

printf "\n================ DONE G16 PROVE ================\n"
