#!/usr/bin/env bash

############################################
################### INIT ###################
############################################

############################################
# Imports

# Get the path to the directory this script is in.
G16_VERIFY_PATH="$(realpath "${BASH_SOURCE[-1]}")"
G16_VERIFY_DIRECTORY="$(dirname "$G16_VERIFY_PATH")"

# Inspiration taken from
# https://stackoverflow.com/questions/12815774/importing-functions-from-a-shell-script/76241268#76241268
. "$G16_VERIFY_DIRECTORY/lib/error_handling.sh"
. "$G16_VERIFY_DIRECTORY/lib/cmd_executor.sh"
. "$G16_VERIFY_DIRECTORY/lib/g16_utils.sh"

############################################
# Constants.

ERR_PREFIX="G16 VERIFY ERROR"

############################################
################## SETUP ###################
############################################

ERR_MSG="Most likely a bug in the shell script"

print_usage() {
    printf "
Groth16 proof verification for circom circuits.

USAGE:
    ./g16_verify.sh [FLAGS] [OPTIONS] <circuit_path>

DESCRIPTION:
    This script does the following:
    1. Verify the Groth16 proof in <proof_dir>, which is assumed to be a proof for <circuit_path>

FLAGS:

    -b               Big circuits. Perform optimizations for large circuits:
                     - Use patched version of node (path to this must be set with '-n'), see these for more info
                       https://hackmd.io/V-7Aal05Tiy-ozmzTGBYPA#Install-patched-node
                       https://github.com/hermeznetwork/phase2ceremony_4/blob/main/VERIFY.md#adding-swap-and-tweeking-the-os-to-accept-high-amount-of-memory

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

    -t <PATH>        Powers of tau (ptau) file path (used for verifying the zkey, see '-z')

    -Z <PATH>        Path to proving key (zkey)
                     Default is '<build_dir>/<circuit_name>_final.zkey'

ARGS:

    <circuit_path>   Path to a the circom circuit to generate a witness for
"
}

############################################
# Parse flags & optional args.

big_circuits=false
build_dir="$G16_VERIFY_DIRECTORY"/../build
patched_node_path=$PATCHED_NODE_PATH
verbose=false
verify_witness=false
verify_zkey=false
zkey_has_custom_path=false

# https://stackoverflow.com/questions/7069682/how-to-get-arguments-with-flags-in-bash#21128172
while getopts 'bB:hn:p:t:vwzZ:' flag; do
    case "${flag}" in
    b)
        big_circuits=true
        compile_flags="--01 --c"
        ;;
    B) build_dir="${OPTARG}" ;;
    h)
        print_usage
        exit 1
        ;;
    n) patched_node_path="${OPTARG}" ;;
    p) proof_dir="${OPTARG}" ;;
    t) ptau_path="${OPTARG}" ;;
    v) verbose=true ;;
    w) verify_witness=true ;;
    z) verify_zkey=true ;;
    Z)
        zkey_has_custom_path=true
        zkey_path="${OPTARG}"
        ;;
    *)
        print_usage
        exit 1
        ;;
    esac
done

############################################
# Required args.

if [ "$#" -lt 1 ]; then
    ERR_MSG="$ERR_PREFIX: Not enough arguments"
    exit 1
fi

circuit_path="${@: -1}"
check_file_exists_with_ext "$ERR_PREFIX" "circuit_path" "$circuit_path" "circom"

# https://stackoverflow.com/questions/965053/extract-filename-and-extension-in-bash
circuit_file=$(basename $circuit_path)
circuit_name="${circuit_file%.*}"

############################################

if $verbose; then
    # print commands before executing
    set -x
fi

############################################
# Make sure proof directory exists.

if [[ -z "$proof_dir" ]]; then
    echo "Proof directory not set, defaulting to build directory: $build_dir"
    proof_dir="$build_dir"
fi

if [[ ! -d "$proof_dir" ]]; then
    ERR_MSG="$ERR_PREFIX: Proof directory does not exist $proof_dir"
    exit 1
fi

############################################
# Verify/set zkey path & ptau file.

if $verify_zkey; then
    if [[ "${ptau_path##*.}" != "ptau" ]] || [[ ! -f "$ptau_path" ]]; then
        ERR_MSG="$ERR_PREFIX: <ptau_path> '$ptau_path' does not point to an existing ptau file. You must provide a ptau file if you want the zkey to be verified."
        exit 1
        # elif
        # TODO check file hash matches https://github.com/iden3/snarkjs#7-prepare-phase-2
        # TODO verify ptau file https://github.com/iden3/snarkjs#8-verify-the-final-ptau
    fi

    if ! $zkey_has_custom_path; then
        set_default_zkey_path_final "$build_dir" "$circuit_name" zkey_path
    fi

    verify_zkey_path "$zkey_path" "$ERR_PREFIX"
fi

############################################
# Setup for big circuits.

if $big_circuits; then
    verify_patched_node_path "$patched_node_path" "$ERR_PREFIX"
fi

############################################
# Reset error message.

ERR_MSG="UNKNOWN"

############################################
################ COMMANDS ##################
############################################

MSG="VERIFYING FINAL ZKEY"
if $verify_zkey; then
    if $big_circuits; then
        execute "$patched_node_path" $NODE_CLI_OPTIONS "$SNARKJS_CLI" zkey verify \
                "$build_dir"/"$circuit_name".r1cs \
                "$ptau_path" \
                "$zkey_path"
    else
        execute npx snarkjs zkey verify \
                "$build_dir"/"$circuit_name".r1cs \
                "$ptau_path" \
                "$zkey_path"
    fi
fi

MSG="VERIFYING WITNESS"
if $verify_witness; then
    execute snarkjs wtns check \
            "$build_dir"/"$circuit_name".r1cs \
            "$proof_dir"/witness.wtns
fi

MSG="VERIFYING PROOF"
execute npx snarkjs groth16 verify \
        "$build_dir"/"$circuit_name"_vkey.json \
        "$proof_dir"/public.json \
        "$proof_dir"/proof.json

printf "\n================ DONE G16 VERIFY ================\n"
