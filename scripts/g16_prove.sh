#!/usr/bin/env bash

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
. "$G16_SETUP_DIRECTORY/lib/g16_utils.sh"

############################################
# Constants.

ERR_PREFIX="G16 PROVE ERROR"

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

    -Z <PATH>        Path to proving key (zkey)
                     Default is '<build_dir>/<circuit_name>_final.zkey'

ARGS:

    <circuit_path>   Path to a the circom circuit to generate a witness for

    <signals_path>   Path to the json file containing the input signals for the circuit
"
}

############################################
# Parse flags & optional args.

big_circuits=false
build_dir="$G16_PROVE_DIRECTORY"/../build
patched_node_path=$PATCHED_NODE_PATH
rapidsnark_path=$RAPIDSNARK_PATH
quick=false
verbose=false
zkey_has_custom_path=false

# https://stackoverflow.com/questions/7069682/how-to-get-arguments-with-flags-in-bash#21128172
while getopts 'bB:hn:p:qr:vZ:' flag; do
    case "${flag}" in
    b)
        big_circuits=true
        compile_flags="--01 --c"
        ;;
    B) build_dir="${OPTARG}" ;;
    h)
        print_usage
        exit 0
        ;;
    n) patched_node_path="${OPTARG}" ;;
    p) proof_dir="${OPTARG}" ;;
    q) quick=true ;;
    r) rapidsnark_path="${OPTARG}" ;;
    v) verbose=true ;;
    Z)
        zkey_has_custom_path=true
        zkey_path="${OPTARG}"
        ;;
    *)
        print_usage
        exit 0
        ;;
    esac
done

############################################
# Required args.

if [ "$#" -lt 2 ]; then
    ERR_MSG="$ERR_PREFIX: Not enough arguments"
    exit 1
fi

# https://stackoverflow.com/questions/11054939/how-to-get-the-second-last-argument-from-shell-script#11055032
circuit_path="${@:(-2):1}"
signals_path="${@: -1}"

check_file_exists_with_ext "$ERR_PREFIX" "circuit_path" "$circuit_path" "circom"
check_file_exists_with_ext "$ERR_PREFIX" "signals_path" "$signals_path" "json"

# https://stackoverflow.com/questions/965053/extract-filename-and-extension-in-bash
circuit_file=$(basename $circuit_path)
circuit_name="${circuit_file%.*}"

############################################

if $verbose; then
    # print commands before executing
    set -x
fi

############################################
# Verify build directory exists.

if [[ ! -d "$build_dir" ]]; then
    ERR_MSG="Build directory $build_dir does not exist"
    exit 1
fi

############################################
# Make sure proof directory exists.

if [[ -z "$proof_dir" ]]; then
    echo "Proof directory not set, defaulting to build directory: $build_dir"
    proof_dir="$build_dir"
fi

if [[ ! -d "$proof_dir" ]]; then
    echo "Creating proof directory $proof_dir"
    mkdir -p "$proof_dir"
fi

############################################
# Verify/set zkey path.

if ! $zkey_has_custom_path; then
    set_default_zkey_path_final "$build_dir" "$circuit_name" zkey_path
fi

verify_zkey_path "$zkey_path" "$ERR_PREFIX"

############################################
# Setup for big circuits.

if $big_circuits; then
    verify_patched_node_path "$patched_node_path" "$ERR_PREFIX"

    if [[ -z "$rapidsnark_path" ]]; then
        ERR_MSG="$ERR_PREFIX: Path to rapidsnark binary not set. This must be set if using '-b'."
        exit 1
    fi

    rapidsnark_file=$(basename "$rapidsnark_path")
    if [[ ! -f "$rapidsnark_path" ]] || [[ $rapidsnark_file != "prover" ]]; then
        ERR_MSG="$ERR_PREFIX: $rapidsnark_path must point to a file with name 'prover'"
        exit 1
    fi

    expected_wtns_gen_path="$build_dir"/"$circuit_name"_cpp/"$circuit_name"
else
    expected_wtns_gen_path="$build_dir"/"$circuit_name"_js/generate_witness.js
fi

if [[ ! -f "$expected_wtns_gen_path" ]]; then
    ERR_MSG="$ERR_PREFIX: The witness generation code does not exist at the expected path $expected_wtns_gen_path"
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

if $big_circuits; then
    MSG="GENERATING WITNESS USING C++ CODE"
    execute "$build_dir"/"$circuit_name"_cpp/"$circuit_name" "$signals_path" "$proof_dir"/witness.wtns
else
    MSG="GENERATING WITNESS USING WASM CODE"
    execute npx node "$build_dir"/"$circuit_name"_js/generate_witness.js "$build_dir"/"$circuit_name"_js/"$circuit_name".wasm "$signals_path" "$proof_dir"/witness.wtns
fi

if $quick; then
    printf "\n================ SKIPPING PROOF GENERATION DUE TO SHORT-CIRCUIT FLAG -q ================"
    exit 0
fi

if $big_circuits; then
    MSG="GENERATING PROOF USING RAPIDSNARK"
    execute "$rapidsnark_path" "$zkey_path" "$proof_dir"/witness.wtns "$proof_dir"/proof.json "$proof_dir"/public.json
else
    MSG="GENERATING PROOF USING SNARKJS"
    execute npx snarkjs groth16 prove "$zkey_path" "$proof_dir"/witness.wtns "$proof_dir"/proof.json "$proof_dir"/public.json
fi

printf "\n================ DONE G16 PROVE ================\n"
