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

############################################
################## CLI #####################
############################################

ERR_MSG="$ERR_PREFIX: Most likely a bug in the shell script"

build_dir="$PROJECT_ROOT_DIR"/build
ptau_path="$FULL_WORKFLOW_DIR"/../powersOfTau28_hez_final.ptau

print_usage() {
    printf "
Proof of Assets ZK proof workflow.

USAGE:
    ./full_workflow.sh [FLAGS] [OPTIONS] <signatures_path> <anonymity_set_path> <blinding_factor>

DESCRIPTION:
    Note that only the Ethereum blockchain is currently supported.

    This script does the following:
    1. Converts the given ECDSA signatures to ECDSA* signatures, which are required for the circuits
    2. Generates the final Circom circuits based on the pre-written templates & the provided inputs
    3. Generate a Merkle Tree for the anonymity set
    4. Invoke g16_setup.sh for the 3 layers to generate the proving keys (zkeys) (done in parallel by default)
    5. Save the zkeys in the zkey directory, for reuse in future runs
    6. Invoke g16_prove.sh for all batches of layers 1 & 2, in parallel
    7. Invoke g16_prove.sh for final layer 3 circuit

FLAGS:

    -s                      Run the circuit setup script (g16_setup.sh) sequentially for all layers
                            The default is to run the setup for each layer in parallel,
                              but it can be very resource-hungry (depending on number of signatures)
                              and if the machine does not have the resources then running
                              in parallel will be slower than running sequentially.

    -v                      Print commands that are run (set -x)

    -h                      Help (print this text)

OPTIONS:

    -b <NUM>                Ideal batch size (this may not be the resulting batch size)
                            Default is 'ceil(num_sigs / 5)'

    -B <PATH>               Build directory, where all the build artifacts are placed
                            Default is $build_dir

    -p <PATH>               Ptau file to be used for generating groth16 proofs
                            Default is $ptau_path

ARGS:

    <signatures_path>       Path to the json file containing the ECDSA signatures of the owned accounts
                            The json file should be a list of entries of the form:
                            {
                              "address": "0x72d0de0955fdba5f62af04b6d1029e4a5fdba5f6",
                              "balance": "5940527217576722726n",
                              "signature": {
                                "v": 28,
                                "r": "0x4b192b5b734f7793e28313a9f269f1f3ad1e0587a395640f8f994abdb5d750a2",
                                "s": "0xdba067cd36db3a3603649fdbb397d466021e6ef0307a41478b9aaeb47d0df6a5",
                                "msghash": "0x5f8465236e0a23dff20d042e450704e452513ec41047dd0749777b1ff0717acc"
                              }
                            }

    <anonymity_set_path>    Path to the CSV file containing the anonymity set of addresses & balances
                            Headings should be \"address,eth_balance\"

    <blinding_factor>       Blinding factor for the Pedersen commitment
                            The Pedersen commitments are done on the 25519 elliptic curve group
                            Must be a decimal value less than '2^255 - 19'
"
}

############################################
# Parse flags & optional args.

verbose=false
sequential_setup=false

# https://stackoverflow.com/questions/7069682/how-to-get-arguments-with-flags-in-bash#21128172
while getopts 'b:B:p:shv' flag; do
    case "${flag}" in
    b) ideal_num_sigs_per_batch="${OPTARG}" ;;
    B) build_dir="${OPTARG}" ;;
    p) ptau_path="${OPTARG}" ;;
    s) sequential_setup=true ;;
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
        # TODO 5 is a fairly arbitrary choice, maybe find a better one?
        ideal_num_sigs_per_batch=$((num_sigs / 5))
    else
        ideal_num_sigs_per_batch=$num_sigs
    fi
fi

############################################
# Check ptau.

check_file_exists_with_ext "$ERR_PREFIX" "ptau_path" "$ptau_path" "ptau"

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

if [[ -z $num_sigs ||
    -z $anon_set_size ||
    -z $merkle_tree_height ||
    -z $parallelism ||
    -z $num_sigs_per_batch ||
    -z $remainder ]] \
    ; then

    printf "
$ERR_PREFIX
At least one of the following parameters is was unable to be set:
    num_sigs: '$num_sigs'
    anon_set_size: '$anon_set_size'
    merkle_tree_height: '$merkle_tree_height'
    parallelism: '$parallelism'
    num_sigs_per_batch: '$num_sigs_per_batch'
    remainder: '$remainder'
"

    ERR_MSG="$ERR_PREFIX: Parameter not set (see above)"
    exit 1
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

# Accepts different forms of names for layers 1, 2, 3,
# and returns a stardardized form.
parse_layer_name() {
    # This line allows the function to return a value to the variable provided
    # by the caller. So you call it like this:
    # parse_layer_name $input_variable_name output_variable_name
    declare -n ret=$2

    naming_map=(zero one two three)

    if [[ $1 == 1 || $1 == 2 || $1 == 3 ]]; then
        ret=${naming_map[$1]}
    elif [[ $1 == one || $1 == two || $1 == three || $1 == one_remainder || $1 == two_remainder ]]; then
        ret=$1
    else
        ERR_MSG="$ERR_PREFIX: [likely a bug] Invalid layer selection: $1"
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
    ret="ptau_path"
}

set_signals_path() {
    declare -n ret=$2
    local name
    parse_layer_name $1 name
    ret="$build_dir"/layer_"$name"_input.json
}

set_existing_zkey_path() {
    declare -n ret=$2
    local name

    parse_layer_name $1 name

    if [[ $name == one ]]; then
        ret="$ZKEY_DIR"/layer_one_"$num_sigs_per_batch"_sigs.zkey
    elif [[ $name == one_remainder ]]; then
        ret="$ZKEY_DIR"/layer_one_"$remainder"_sigs.zkey
    elif [[ $name == two ]]; then
        ret="$ZKEY_DIR"/layer_two_"$num_sigs_per_batch"_sigs_"$merkle_tree_height"_height.zkey
    elif [[ $name == two_remainder ]]; then
        ret="$ZKEY_DIR"/layer_two_"$remainder"_sigs_"$merkle_tree_height"_height.zkey
    elif [[ $name == three ]]; then
        ret="$ZKEY_DIR"/layer_three_"$parallelism"_batches.zkey
    else
        ERR_MSG="$ERR_PREFIX: [likely a bug] Invalid layer selection for existing zkey path: $name"
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

    set_existing_zkey_path $1 zkey_path

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
execute npx ts-node "$SCRIPTS_DIR"/ecdsa_sigs_parser.ts \
    --signatures "$sigs_path" \
    --output-path "$parsed_sigs_path"

circuits_relative_path=$(realpath --relative-to="$build_dir" "$CIRCUITS_DIR")

MSG="GENERATING CIRCUITS"
execute npx ts-node "$SCRIPTS_DIR"/generate_circuits.ts \
    --num-sigs $num_sigs_per_batch \
    --num-sigs-remainder $remainder \
    --tree-height $merkle_tree_height \
    --parallelism $parallelism \
    --write-circuits-to "$build_dir" \
    --circuits-library-relative-path "$circuits_relative_path"

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

############################################
### G16 SETUP FOR ALL LAYERS, IN PARALLEL ##
############################################

setup_layer() {
    local build circuit ptau zkey

    set_layer_build_dir $1 build
    set_circuit_path $1 circuit
    set_ptau_path $1 ptau
    set_zkey_arg $1 zkey

    # TODO check number of sigs and only do the -b flag if there are more than 10M constraints
    "$SCRIPTS_DIR"/g16_setup.sh -b -B "$build" -t "$ptau" $zkey "$circuit"
}

# If there are some remainder sigs then we need to run layer 1 & 2 an extra time.
if [[ $remainder -gt 0 ]]; then
    setup_remainder_inputs="one_remainder two_remainder"
fi

# these need to be exported for the parallel command
export -f setup_layer set_layer_build_dir set_ptau_path set_zkey_arg parse_layer_name set_existing_zkey_path
export SCRIPTS_DIR FULL_WORKFLOW_DIR ZKEY_DIR
export threshold parallelism num_sigs num_sigs_per_batch build_dir logs_dir remainder

layers="one two three $setup_remainder_inputs"

# the caller may want to run the setups sequentially, because they can be quite
# compute/memory hungry, and if the machine does not have the resources then
# running them in parallel will actually be slower than running sequentially
if $sequential_setup; then
    generate_merkle_tree

    printf "\n================ RUNNING G16 SETUP FOR ALL LAYERS (SEQUENTIALLY) ================\nSEE $logs_dir/layer_\$layer_setup.log\n================\n"

    for layer in $layers; do
        printf "\n================ RUNNING G16 SETUP FOR LAYER $layer ================\nSEE $logs_dir/layer_\$layer_setup.log\n================\n"

        setup_layer $layer > "$logs_dir"/layer_"$layer"_setup.log
    done
else
    # This section (and others) use GNU's parallel.
    # https://www.baeldung.com/linux/bash-for-loop-parallel#4-gnu-parallel-vs-xargs-for-distributing-commands-to-remote-servers
    # https://www.gnu.org/software/parallel/parallel_examples.html#example-rewriting-a-for-loop-and-a-while-read-loop

    printf "\n================ RUNNING G16 SETUP FOR ALL LAYERS (IN PARALLEL, ALSO PARALLEL TO MERKLE TREE BUILD) ================\nSEE $logs_dir/layer_\$layer_setup.log\n================\n"

    generate_merkle_tree &
    parallel --joblog "$logs_dir/setup_layer.log" setup_layer {} '>' "$logs_dir"/layer_{}_setup.log '2>&1' ::: $layers

    wait
fi

############################################
######### MOVE ZKEYS TO ZKEY DIR ###########
############################################

move_zkey() {
    local _name zkey_path_build zkey_path_save

    parse_layer_name $1 _name
    set_generated_zkey_path $1 zkey_path
    set_existing_zkey_path $1 zkey_path_save

    if [[ -f "$zkey_path" ]]; then
        mv "$zkey_path" "$zkey_path_save"
    fi
}

# these need to be exported for the parallel command
export -f move_zkey set_generated_zkey_path

printf "
================ MOVING GENERATED ZKEYS TO "$ZKEY_DIR"================
"

parallel move_zkey ::: one two three $setup_remainder_inputs

############################################
####### LAYER 1 & 2 PROVE IN PARALLEL ######
############################################

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
    execute npx ts-node "$SCRIPTS_DIR"/input_prep_for_layer_one.ts \
        --poa-input-data "$parsed_sigs_path" \
        --write-layer-one-data-to "$signals" \
        --account-start-index $start_index \
        --account-end-index $end_index

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
    execute npx ts-node "$SCRIPTS_DIR"/input_prep_for_layer_two.ts \
        --poa-input-data "$parsed_sigs_path" \
        --merkle-root "$merkle_root_path" \
        --merkle-proofs "$merkle_proofs_path" \
        --layer-one-sanitized-proof "$l1_proof_dir"/sanitized_proof.json \
        --write-layer-two-data-to "$signals" \
        --account-start-index $start_index \
        --account-end-index $end_index

    MSG="RUNNING PROVING SYSTEM FOR LAYER 2 CIRCUIT BATCH $i"
    printf "\n================ $MSG ================\n"

    "$SCRIPTS_DIR"/g16_prove.sh -b -B "$build" -p "$l2_proof_dir" $zkey "$circuit" "$signals"
    "$SCRIPTS_DIR"/g16_verify.sh -b -B "$build" -p "$l1_proof_dir" $zkey "$circuit"

    MSG="CONVERTING LAYER 2 PROOF TO LAYER 3 INPUT SIGNALS"
    execute python "$SCRIPTS_DIR"/sanitize_groth16_proof.py "$l2_proof_dir"
}

# these need to be exported for the parallel command
export -f prove_layers_one_two set_signals_path
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
execute npx ts-node "$SCRIPTS_DIR"/input_prep_for_layer_three.ts \
    --merkle-root "$merkle_root_path" \
    --layer-two-sanitized-proof "$build" \
    --multiple-proofs \
    --write-layer-three-data-to "$signals" \
    --blinding-factor $blinding_factor

MSG="RUNNING PROVING SYSTEM FOR LAYER THREE CIRCUIT"
printf "\n================ $MSG ================\n"

"$SCRIPTS_DIR"/g16_prove.sh -b -B "$build" $zkey "$circuit" "$signals"

MSG="VERIFYING FINAL PEDERSEN COMMITMENT"
execute npx ts-node "$SCRIPTS_DIR"/pedersen_commitment_checker.ts \
    --layer-three-public-inputs "$build"/public.json \
    --blinding-factor $blinding_factor

echo "SUCCESS"
