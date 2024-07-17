#!/usr/bin/env bash

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
. "$G16_SETUP_DIRECTORY/lib/g16_utils.sh"

############################################
# Constants.

ERR_PREFIX="G16 SETUP ERROR"
PROJECT_ROOT_DIR="$G16_SETUP_DIRECTORY"/..
SNARKJS_CLI="$PROJECT_ROOT_DIR"/node_modules/snarkjs/cli.js
SNARKJS_FILE=$(basename $SNARKJS_CLI)

if [[ ! -f "$SNARKJS_CLI" ]]; then
    ERR_MSG="$ERR_PREFIX: snarkjs not present in node_modules. Maybe run 'pnpm i'?."
    exit 1
fi

# NOTE the script seems to work without these set.
NODE_CLI_OPTIONS="--max-old-space-size=2048000 --initial-old-space-size=2048000 --no-global-gc-scheduling --no-incremental-marking --max-semi-space-size=1024 --initial-heap-size=2048000 --expose-gc"

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

############################################
# Parse flags & optional args.

beacon=false
big_circuits=false
build_dir="$PROJECT_ROOT_DIR"/build/
compile_flags="--wasm"
patched_node_path=$PATCHED_NODE_PATH
quick=false
skip_zkey_gen=false
verbose=false

# https://stackoverflow.com/questions/7069682/how-to-get-arguments-with-flags-in-bash#21128172
while getopts 'bB:hn:qr:t:vZ:' flag; do
    case "${flag}" in
    b)
        big_circuits=true
        compile_flags="--O1 --c"
        ;;
    B) build_dir="${OPTARG}" ;;
    h)
        print_usage
        exit 0
        ;;
    n) patched_node_path="${OPTARG}" ;;
    q) quick=true ;;
    r) beacon=true ;;
    t) ptau_path="${OPTARG}" ;;
    v) verbose=true ;;
    Z)
        skip_zkey_gen=true
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

circuit_path="${@: -1}"

if [[ ! -f "$circuit_path" ]]; then
    ERR_MSG="$ERR_PREFIX: <circuit_path> '$circuit_path' does not point to a file."
    exit 1
fi

# https://stackoverflow.com/questions/965053/extract-filename-and-extension-in-bash
circuit_file=$(basename $circuit_path)
circuit_name="${circuit_file%.*}"

if [[ "${circuit_path##*.}" != "circom" ]] || [[ ! -f "$circuit_path" ]]; then
    ERR_MSG="$ERR_PREFIX: <circuit_path> '$circuit_path' does not point to an existing circom file."
    exit 1
fi

############################################

if $verbose; then
    # print commands before executing
    set -x
fi

############################################
# Make sure build directory exists.

if [[ ! -d "$build_dir" ]]; then
    echo "Creating build directory $build_dir"
    mkdir -p "$build_dir"
fi

############################################
# Setup for big circuits.

if $big_circuits; then
    verify_patched_node_path "$patched_node_path" "$ERR_PREFIX"
fi

############################################
# Verify any provided zkey.

if $skip_zkey_gen; then
    if [[ -z "$zkey_path" ]]; then
        ERR_MSG="$ERR_PREFIX: Path to zkey not set, but -Z option was given."
        exit 1
    fi

    if [[ "${zkey_path##*.}" != "zkey" ]] || [[ ! -f "$zkey_path" ]]; then
        ERR_MSG="$ERR_PREFIX: <zkey_path> '$zkey_path' does not point to an existing zkey file."
        exit 1
    fi
else
    if [[ "${ptau_path##*.}" != "ptau" ]] || [[ ! -f "$ptau_path" ]]; then
        ERR_MSG="$ERR_PREFIX: <ptau_path> '$ptau_path' does not point to an existing ptau file. You must provide a ptau file OR zkey file."
        exit 1
        # elif
        # TODO check file hash matches https://github.com/iden3/snarkjs#7-prepare-phase-2
        # TODO verify ptau file https://github.com/iden3/snarkjs#8-verify-the-final-ptau
    fi
fi

############################################
# Reset error message.

ERR_MSG="UNKNOWN"

############################################
################ COMMANDS ##################
############################################

# Commands were originally from 0xPARC/circom-ecdsa & https://hackmd.io/V-7Aal05Tiy-ozmzTGBYPA

MSG="COMPILING CIRCUIT"
# sym: generates circuit.sym (a symbols file required for debugging and printing the constraint system in an annotated mode).
#
# --O1 optimization only removes “equals” constraints but does not optimize out “linear” constraints.
# the further --O2 optimization takes significantly longer on large circuits (for reasons that aren’t totally clear)
execute circom "$circuit_path" \
        --r1cs $compile_flags \
        --sym \
        --output "$build_dir" \
        -l ./node_modules \
        -l ./git_modules

if $big_circuits; then
    MSG="COMPILING C++ WITNESS GENERATION CODE"
    cd "$build_dir"/"$circuit_name"_cpp
    execute make
    cd -
fi

if $quick; then
    printf "\n================ SKIPPING ZKEY & VKEY GENERATION DUE TO SHORT-CIRCUIT FLAG -q ================"
    exit 0
fi

if ! $skip_zkey_gen; then
    if $big_circuits; then
        MSG="GENERATING ZKEY FOR CIRCUIT USING PATCHED NODE"
        execute "$patched_node_path" $NODE_CLI_OPTIONS "$SNARKJS_CLI" zkey new \
                "$build_dir"/"$circuit_name".r1cs \
                "$ptau_path" \
                "$build_dir"/"$circuit_name"_0.zkey
    else
        MSG="GENERATING ZKEY FOR CIRCUIT"
        execute npx snarkjs groth16 setup \
                "$build_dir"/"$circuit_name".r1cs \
                "$ptau_path" \
                "$build_dir"/"$circuit_name"_0.zkey
    fi

    MSG="CONTRIBUTING TO PHASE 2 CEREMONY"
    if $beacon; then
        suffix="1"
    else
        suffix="final"
    fi
    # TODO allow cli to give random text for entropy
    execute npx snarkjs zkey contribute \
            "$build_dir"/"$circuit_name"_0.zkey \
            "$build_dir"/"$circuit_name"_"$suffix".zkey \
            --name="First contributor" \
            -e="random text for entropy"

    # TODO allow cli to give randomness
    if $beacon; then
        MSG="GENERATING FINAL ZKEY USING RANDOM BEACON"
        # what is this random hex? https://github.com/iden3/snarkjs#20-apply-a-random-beacon
        execute npx snarkjs zkey beacon \
                "$build_dir"/"$circuit_name"_"$suffix".zkey \
                "$build_dir"/"$circuit_name"_final.zkey \
                0102030405060708090a0b0c0d0e0f101112231415161718221a1b1c1d1e1f \
                10 \
                -n="Final Beacon phase2"
    fi

    set_default_zkey_path_final "$build_dir" "$circuit_name" zkey_path
else
    printf "\n================ SKIPPING ZKEY GENERATION, USING EXISTING ZKEY $zkey_path ================"
fi

MSG="EXPORTING VKEY"
if $big_circuits; then
    execute "$patched_node_path" "$SNARKJS_CLI" zkey export verificationkey \
            "$zkey_path" \
            "$build_dir"/"$circuit_name"_vkey.json
else
    execute npx snarkjs zkey export verificationkey -v \
            "$zkey_path" \
            "$build_dir"/"$circuit_name"_vkey.json \
fi

printf "\n================ DONE G16 SETUP ================\n"
