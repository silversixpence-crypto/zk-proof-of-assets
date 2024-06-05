#!/usr/bin/env bash

############################################
################### INIT ###################
############################################

############################################
# Imports

FULL_WORKFLOW_FILE_PATH="$(realpath "${BASH_SOURCE[-1]}")"
FULL_WORKFLOW_DIR="$(dirname "$FULL_WORKFLOW_FILE_PATH")"

. "$FULL_WORKFLOW_DIR/../scripts/lib/error_handling.sh"
. "$FULL_WORKFLOW_DIR/../scripts/lib/cmd_executor.sh"

############################################
# Constants.

ERR_PREFIX="FULL WORKFLOW ERROR"
PROJECT_ROOT_DIR="$FULL_WORKFLOW_DIR"/..
CIRCUITS_DIR="$FULL_WORKFLOW_DIR"/../circuits
SCRIPTS_DIR="$FULL_WORKFLOW_DIR"
ZKEY_DIR="$FULL_WORKFLOW_DIR"/../zkeys

if [[ ! -d "$ZKEY_DIR" ]]; then
    mkdir -p "$ZKEY_DIR"
fi

# TODO remove
BLINDING_FACTOR="4869643893319708471955165214975585939793846505679808910535986866633137979160"

############################################
################### CLI ####################
############################################

ERR_MSG="Most likely a bug in the shell script"

print_usage() {
    printf "
Proof of Assets ZK proof workflow.

USAGE:
    ./full_workflow.sh [FLAGS] [OPTIONS] <signatures_path> <anonymity_set_path> <blinding_factor>

DESCRIPTION:
    This script does the following:
    1. TODO

FLAGS:

OPTIONS:

    -b <NUM>         Ideal batch size (this may not be the resulting batch size)
                     Default is TODO

    -B <PATH>        Build directory, where all the build artifacts are placed
                     Default is '<repo_root_dir>/build'

    -h <NUM>         Merkle tree height
                     Default is TODO

ARGS:

    <signatures_path>       Path to the file containing the signatures of the owned accounts

    <anonymity_set_path>    Path to the anonymity set of addresses

    <blinding_factor>       Blinding factor for the Pedersen commitment
"
}

############################################
# Parse flags & optional args.

build_dir="$PROJECT_ROOT_DIR"/build
verbose=false

# https://stackoverflow.com/questions/7069682/how-to-get-arguments-with-flags-in-bash#21128172
while getopts 'b:B:hv' flag; do
    case "${flag}" in
    b) ideal_num_sigs_per_batch="${OPTARG}" ;;
    B) build_dir="${OPTARG}" ;;
    h)
        print_usage
        exit 0
        ;;
    v) verbose=true ;;
    *)
        print_usage
        exit 0
        ;;
    esac
done

############################################
# Required args.

if [ "$#" -lt 3 ]; then
    ERR_MSG="$ERR_PREFIX: Not enough arguments"
    exit 1
fi

# https://stackoverflow.com/questions/11054939/how-to-get-the-second-last-argument-from-shell-script#11055032
sigs_path="${@:(-3):1}"
anon_set_path="${@:(-2):1}"
blinding_factor="${@: -1}"

############################################
# Check & count sigs & anon set.

check_file_exists_with_ext "$ERR_PREFIX" "sigs_path" "$sigs_path" "json"

num_sigs=$(jq "[ .[] ] | length" $sigs_path)
parsed_sigs_path="$(dirname "$sigs_path")"/input_data_for_"$num_sigs"_accounts.json

check_file_exists_with_ext "$ERR_PREFIX" "anon_set_path" "$anon_set_path" "csv"
anon_set_size=$(cat $anon_set_path | tail -n+2 | wc -l)
merkle_tree_height=$(echo "1 + l($anon_set_size)/l(2)" | bc -l | sed "s/\.[0-9]*//")

# if the batch size is not set by the user then set it automatically
if [ -z "$ideal_num_sigs_per_batch" ]; then
    if [[ $num_sigs > 5 ]]; then
        # 5 is a fairly arbitrary choice
        ideal_num_sigs_per_batch=$((num_sigs / 5))
    else
        ideal_num_sigs_per_batch=$num_sigs
    fi
fi

############################################

if $verbose; then
    # print commands before executing
    set -x
fi

############################################
######### PARALLELISM PARAMETERS ###########
############################################

output=$(python "$SCRIPTS_DIR"/batch_size_optimizooor.py $num_sigs $ideal_num_sigs_per_batch)
num_sigs_per_batch=$(echo $output | grep -o -e "[0-9]*" | sed -n 1p)
remainder=$(echo $output | grep -o -e "[0-9]*" | sed -n 2p)

parallelism=$((num_sigs / num_sigs_per_batch))
if [[ $remainder -gt 0 ]]; then
    parallelism=$((parallelism + 1))
fi

printf "
/////////////////////////////////////////////////////////
Initiating proving system with the following parameters:

- Number of accounts/signatures:   $num_sigs
- Anonymity set size:              $anon_set_size
- Merkle tree height:              $merkle_tree_height
- Number of batches:               $parallelism
- Batch size:                      $num_sigs_per_batch
- Remainder batch size:            $remainder

/////////////////////////////////////////////////////////
"

############################################
########### DIRECTORY BUILDERS #############
############################################

identifier="$num_sigs"_sigs_"$parallelism"_batches_"$merkle_tree_height"_height
build_dir="$build_dir"/$identifier
logs_dir="$build_dir"/logs
merkle_proofs_path="$build_dir"/merkle_proofs.json
merkle_root_path="$build_dir"/merkle_root.json

if [[ ! -d "$logs_dir" ]]; then
    mkdir -p "$logs_dir"
fi

parse_layer_name() {
    declare -n ret=$2

    naming_map=(zero one two three)

    if [[ $1 == 1 || $1 == 2 || $1 == 3 ]]; then
        ret=${naming_map[$1]}
    elif [[ $1 == one || $1 == two || $1 == three || $1 == one_remainder || $1 == two_remainder ]]; then
        ret=$1
    else
        ERR_MSG="[likely a bug] Invalid layer selection: $1"
        exit 1
    fi
}

set_layer_build_dir() {
    declare -n ret=$2
    local name
    parse_layer_name $1 name
    ret="$build_dir"/layer_"$name"
}

set_circuit_path() {
    declare -n ret=$2
    local name
    parse_layer_name $1 name
    ret="$build_dir"/layer_"$name".circom
}

set_ptau_path() {
    declare -n ret=$2
    local _name
    parse_layer_name $1 _name
    ret="$FULL_WORKFLOW_DIR"/../powersOfTau28_hez_final.ptau
}

set_signals_path() {
    declare -n ret=$2
    local name
    parse_layer_name $1 name
    ret="$build_dir"/layer_"$name"_input.json
}

set_exitsting_zkey_path() {
    declare -n ret=$2
    local name

    parse_layer_name $1 name

    if [[ $name == one || $name == one_remainder ]]; then
        ret="$ZKEY_DIR"/layer_one_"$num_sigs"_sigs.zkey
    elif [[ $name == two || $name == two_remainder ]]; then
        ret="$ZKEY_DIR"/layer_two_"$num_sigs"_sigs_"$merkle_tree_height"_height.zkey
    elif [[ $name == three ]]; then
        ret="$ZKEY_DIR"/layer_three_"$parallelism"_batches.zkey
    else
        ERR_MSG="[likely a bug] Invalid layer selection for existing zkey path: $name"
        exit 1
    fi
}

set_generated_zkey_path() {
    declare -n ret=$2
    local name build

    parse_layer_name $1 name
    set_layer_build_dir $1 build

    ret="$build"/layer_"$name"_final.zkey
}

set_zkey_arg() {
    declare -n ret=$2
    local zkey_path

    set_exitsting_zkey_path $1 zkey_path

    if [[ -f "$zkey_path" ]]; then
        zkey_arg="-Z $zkey_path"
    else
        zkey_arg=""
    fi

    ret="$zkey_arg"
}

############################################
############# DATA GENERATION ##############
############################################

MSG="PARSING SIGNATURES"
execute npx ts-node "$SCRIPTS_DIR"/ecdsa_sigs_parser.ts -s "$sigs_path" --output-path "$parsed_sigs_path"

circuits_relative_path=$(realpath --relative-to="$build_dir" "$CIRCUITS_DIR")

MSG="GENERATING CIRCUITS"
execute npx ts-node "$SCRIPTS_DIR"/generate_circuits.ts --num-sigs $num_sigs_per_batch --num-sigs-remainder $remainder --tree-height $merkle_tree_height --parallelism $parallelism --write-circuits-to "$build_dir" --circuits-library-relative-path "$circuits_relative_path"

# Run in parallel to the next commands, 'cause it takes long
generate_merkle_tree() {
    MSG="GENERATING MERKLE TREE FOR ANONYMITY SET, AND MERKLE PROOFS FOR OWNED ADDRESSES"
    printf "\n================ $MSG ================\nSEE $logs_dir/merkle_tree.log\n"

    RUSTFLAGS=-Awarnings execute cargo run --bin merkle-tree -- \
        --anon-set "$anon_set_path" \
        --poa-input-data "$parsed_sigs_path" \
        --output-dir "$build_dir" \
    &>"$logs_dir"/merkle_tree.log
}

generate_merkle_tree

exit 0

############################################
### G16 SETUP FOR ALL LAYERS, IN PARALLEL ##
############################################

setup_layers() {
    local build circuit ptau zkey

    set_layer_build_dir $1 build
    set_circuit_path $1 circuit
    set_ptau_path $1 ptau
    set_zkey_arg $1 zkey

    # TODO check number of sigs and only do the -b flag if there are more than 10M constraints
    "$SCRIPTS_DIR"/g16_setup.sh -b -B "$build" -t "$ptau" $zkey "$circuit"
}

if [[ $remainder -gt 0 ]]; then
    setup_remainder_inputs="one_remainder two_remainder"
fi

# these need to be exported for the parallel command
export -f setup_layers set_layer_build_dir set_ptau_path set_zkey_arg set_sigs_path parse_layer_name set_exitsting_zkey_path
export SCRIPTS_DIR FULL_WORKFLOW_DIR
export threshold parallelism num_sigs build_dir logs_dir

printf "
================ RUNNING G16 SETUP FOR ALL LAYERS ================
SEE $logs_dir/layer_\$layer_setup.log
================
"

generate_merkle_tree &
parallel --joblog "$logs_dir/setup_layers.log" setup_layers {} '>' "$logs_dir"/layer_{}_setup.log '2>&1' ::: one two three $setup_remainder_inputs

wait

############################################
######### MOVE ZKEYS TO ZKEY DIR ###########
############################################

move_zkey() {
    local _name zkey_path_build zkey_path_save

    parse_layer_name $1 _name
    set_generated_zkey_path $1 zkey_path
    set_exitsting_zkey_path $1 zkey_path_save

    if [[ -f "$zkey_path" ]]; then
        mv "$zkey_path" "$zkey_path_save"
    fi
}

# these need to be exported for the parallel command
export -f move_zkey generated_zkey_path

parallel move_zkey ::: one two three $setup_remainder_inputs

############################################
####### LAYER 1 & 2 PROVE IN PARALLEL ######
############################################

# Use GNU's parallel.
# https://www.baeldung.com/linux/bash-for-loop-parallel#4-gnu-parallel-vs-xargs-for-distributing-commands-to-remote-servers
# https://www.gnu.org/software/parallel/parallel_examples.html#example-rewriting-a-for-loop-and-a-while-read-loop

prove_layers_one_two() {
    i=$1 # batch number

    # Re-import these 'cause they don't seem to come through the parallel command.
    . "$FULL_WORKFLOW_DIR/../scripts/lib/error_handling.sh"
    . "$FULL_WORKFLOW_DIR/../scripts/lib/cmd_executor.sh"

    local start_index end_index build signals circuit zkey proof

    # Index range of the signature set to be done in this batch.
    start_index=$((i * threshold))
    if [[ $i -eq $((parallelism - 1)) ]]; then
        end_index=$num_sigs
    else
        end_index=$((start_index + threshold)) # not inclusive
    fi

    # Setup layer 1 path variables.
    set_layer_build_dir 1 build
    set_signals_path 1 signals
    set_circuit_path 1 circuit
    set_zkey_arg 1 zkey

    l1_proof_dir="$build"/batch_"$i"
    if [[ ! -d "$l1_proof_dir" ]]; then
        mkdir -p "$l1_proof_dir"
    fi

    MSG="PREPARING INPUT SIGNALS FILE FOR LAYER 1 CIRCUIT BATCH $i"
    execute npx ts-node "$SCRIPTS_DIR"/input_prep_for_layer_one.ts --poa-input-data "$parsed_sigs_path" --write-layer-one-data-to "$signals" --account-start-index $start_index --account-end-index $end_index

    "$SCRIPTS_DIR"/g16_prove.sh -b -B "$build" -p "$l1_proof_dir" $zkey "$circuit" "$signals"
    "$SCRIPTS_DIR"/g16_verify.sh -b -B "$build" -p "$l1_proof_dir" $zkey "$circuit"

    # Setup layer 2 path variables.
    set_layer_build_dir 2 build
    set_signals_path 2 signals
    set_circuit_path 2 circuit
    set_zkey_arg 2 zkey

    l2_proof_dir="$build"/batch_"$i"
    if [[ ! -d "$l2_proof_dir" ]]; then
        mkdir -p "$l2_proof_dir"
    fi

    MSG="CONVERTING LAYER 1 PROOF TO LAYER 2 INPUT SIGNALS BATCH $i"
    execute python "$SCRIPTS_DIR"/sanitize_groth16_proof.py "$l1_proof_dir"

    MSG="PREPARING INPUT SIGNALS FILE FOR LAYER 2 CIRCUIT BATCH $i"
    execute npx ts-node "$SCRIPTS_DIR"/input_prep_for_layer_two.ts --poa-input-data "$parsed_sigs_path" --merkle-root "$merkle_root_path" --merkle-proofs "$merkle_proofs_path" --layer-one-sanitized-proof "$l1_proof_dir"/sanitized_proof.json --write-layer-two-data-to "$signals" --account-start-index $start_index --account-end-index $end_index

    MSG="RUNNING PROVING SYSTEM FOR LAYER 2 CIRCUIT BATCH $i"
    printf "\n================ $MSG ================\n"

    "$SCRIPTS_DIR"/g16_prove.sh -b -B "$build" -p "$l2_proof_dir" $zkey "$circuit" "$signals"
    "$SCRIPTS_DIR"/g16_verify.sh -b -B "$build" -p "$l1_proof_dir" $zkey "$circuit"

    MSG="CONVERTING LAYER 2 PROOF TO LAYER 3 INPUT SIGNALS"
    execute python "$SCRIPTS_DIR"/sanitize_groth16_proof.py "$l2_proof_dir"
}

# these need to be exported for the parallel command
export -f prove_layers_one_two
export parsed_sigs_path merkle_root_path merkle_proofs_path

printf "
================ PROVING ALL BATCHES OF LAYERS 1 & 2 IN PARALLEL ================
SEE $logs_dir/layers_one_two_prove_batch_\$i.log
OR $logs_dir/layers_one_two_prove.log
================
"

seq 0 $((parallelism - 1)) | parallel --joblog "$logs_dir/layers_one_two_prove.log" prove_layers_one_two {} '>' "$logs_dir"/layers_one_two_prove_batch_{}.log '2>&1'

############################################
############# LAYER 3 PROVE ################
############################################

# Setup layer 3 path variables.
set_layer_build_dir 3 build
set_signals_path 3 signals
set_circuit_path 3 circuit
set_zkey_arg 3 zkey

MSG="PREPARING INPUT SIGNALS FILE FOR LAYER THREE CIRCUIT"
execute npx ts-node "$SCRIPTS_DIR"/input_prep_for_layer_three.ts --merkle-root "$merkle_root_path" --layer-two-sanitized-proof "$build" --multiple-proofs --write-layer-three-data-to "$signals" --blinding-factor $BLINDING_FACTOR

MSG="RUNNING PROVING SYSTEM FOR LAYER THREE CIRCUIT"
printf "\n================ $MSG ================\n"

"$SCRIPTS_DIR"/g16_prove.sh -b -B "$build" $zkey "$circuit" "$signals"

MSG="VERIFYING FINAL PEDERSEN COMMITMENT"
execute npx ts-node "$SCRIPTS_DIR"/pedersen_commitment_checker.ts --layer-three-public-inputs "$build"/public.json --blinding-factor $BLINDING_FACTOR

echo "SUCCESS"
