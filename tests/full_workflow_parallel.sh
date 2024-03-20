#!/usr/bin/env bash

THIS_FILE_PATH="$(realpath "${BASH_SOURCE[-1]}")"
THIS_DIR="$(dirname "$THIS_FILE_PATH")"

. "$THIS_DIR/../scripts/lib/error_handling.sh"
. "$THIS_DIR/../scripts/lib/cmd_executor.sh"

# ///////////////////////////////////////////////////////
# Variables.

num_sigs=3
anon_set_size=1000
merkle_tree_height=14
ideal_num_sigs_per_batch=2

output=$(python "$THIS_DIR"/../scripts/batch_size_calculator.py $num_sigs $ideal_num_sigs_per_batch)
num_sigs_per_batch=2 # $(echo $output | grep -o -e "[0-9]*" | sed -n 1p)
remainder=1 # $(echo $output | grep -o -e "[0-9]*" | sed -n 2p)

parallelism=$((num_sigs / num_sigs_per_batch))
if [[ $remainder -gt 0 ]]; then
    parallelism=$((parallelism + 1))
fi

printf "
/////////////////////////////////////////////////////////
Initiating test with the following parameters:

- Number of accounts/signatures:   $num_sigs
- Anonymity set size:              $anon_set_size
- Merkle tree height:              $merkle_tree_height
- Number of batches:               $parallelism
- Batch size:                      $num_sigs_per_batch
- Remainder batch size:            $remainder

/////////////////////////////////////////////////////////
"

# ///////////////////////////////////////////////////////
# Constants.

IDENTIFIER="$num_sigs"_sigs_"$parallelism"_batches_"$merkle_tree_height"_height

BUILD_DIR="$THIS_DIR"/../build/tests/$IDENTIFIER
CIRCUITS_DIR="$THIS_DIR"/../circuits
LOGS_DIR="$TESTS_DIR"/logs
MERKLE_PROOFS_PATH="$THIS_DIR"/merkle_proofs.json
MERKLE_ROOT_PATH="$THIS_DIR"/merkle_root.json
POA_INPUT_PATH="$THIS_DIR"/input_data_for_"$num_sigs"_accounts.json
SCRIPTS_DIR="$THIS_DIR"/../scripts
TESTS_DIR="$THIS_DIR"/$IDENTIFIER
ZKEY_DIR="$THIS_DIR"/../zkeys

BLINDING_FACTOR="4869643893319708471955165214975585939793846505679808910535986866633137979160"

# ///////////////////////////////////////////////////////
# Create directories.

if [[ ! -d "$TESTS_DIR" ]]; then
    mkdir -p "$TESTS_DIR"
fi

if [[ ! -d "$LOGS_DIR" ]]; then
    mkdir -p "$LOGS_DIR"
fi

if [[ ! -d "$ZKEY_DIR" ]]; then
    mkdir -p "$ZKEY_DIR"
fi

# ///////////////////////////////////////////////////////
# Various path builders for each layer.

naming_map=(zero one two three)

parse_layer_name() {
    declare -n ret=$2

    if [[ $1 == 1 || $1 == 2 || $1 == 3 ]]; then
        ret=${naming_map[$1]}
    elif [[ $1 == one || $1 == two || $1 == three || $1 == one_remainder || $1 == two_remainder ]]; then
        ret=$1
    else
        ERR_MSG="[likely a bug] Invalid layer selection: $1"
        exit 1
    fi
}

build_dir() {
    declare -n ret=$2
    local name
    parse_layer_name $1 name
    ret="$BUILD_DIR"/layer_"$name"
}

circuit_path() {
    declare -n ret=$2
    local name
    parse_layer_name $1 name
    ret="$TESTS_DIR"/layer_"$name".circom
}

ptau_path() {
    declare -n ret=$2
    local _name
    parse_layer_name $1 _name
    ret="$THIS_DIR"/../powersOfTau28_hez_final.ptau
}

signals_path() {
    declare -n ret=$2
    local name
    parse_layer_name $1 name
    ret="$TESTS_DIR"/layer_"$name"_input.json
}

exitsting_zkey_path() {
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

generated_zkey_path() {
    declare -n ret=$2
    local name build

    parse_layer_name $1 name
    build_dir $1 build

    ret="$build"/layer_"$name"_final.zkey
}

zkey_arg() {
    declare -n ret=$2
    local zkey_path

    exitsting_zkey_path $1 zkey_path

    if [[ -f "$zkey_path" ]]; then
        zkey_arg="-Z $zkey_path"
    else
        zkey_arg=""
    fi

    ret="$zkey_arg"
}

# ///////////////////////////////////////////////////////
# Data generation

circuits_relative_path=$(realpath --relative-to="$TESTS_DIR" "$CIRCUITS_DIR")

MSG="GENERATING TEST CIRCUITS"
execute npx ts-node "$THIS_DIR"/generate_test_circuits.ts --num-sigs $num_sigs_per_batch --num-sigs-remainder $remainder --tree-height $merkle_tree_height --parallelism $parallelism --write-circuits-to "$TESTS_DIR" --circuits-library-relative-path "$circuits_relative_path"

MSG="GENERATING TEST INPUT FOR PROOF OF ASSETS PROTOCOL"
execute npx ts-node "$THIS_DIR"/generate_test_input.ts --num-sigs $num_sigs --message "message to sign"

MSG="GENERATING ANONYMITY SET"
execute npx ts-node "$THIS_DIR"/generate_anon_set.ts --num-addresses $anon_set_size

# Run in parallel to the next commands, 'cause it takes long
generate_merkle_tree() {
    MSG="GENERATING MERKLE TREE FOR ANONYMITY SET, AND MERKLE PROOFS FOR OWNED ADDRESSES"
    printf "\n================ $MSG ================\nSEE $LOGS_DIR/merkle_tree.log\n"

    execute npx ts-node "$SCRIPTS_DIR"/merkle_tree.ts \
        --anonymity-set "$THIS_DIR"/anonymity_set.json \
        --poa-input-data "$POA_INPUT_PATH" \
        --output-dir "$THIS_DIR" \
        --height $merkle_tree_height \
        >"$LOGS_DIR"/merkle_tree.log
}

# ///////////////////////////////////////////////////////
# G16 setup for all layers, in parallel.

setup_layers() {
    local build circuit ptau zkey

    build_dir $1 build
    circuit_path $1 circuit
    ptau_path $1 ptau
    zkey_arg $1 zkey

    # TODO check number of sigs and only do the -b flag if there are more than 10M constraints
    "$SCRIPTS_DIR"/g16_setup.sh -b -B "$build" -t "$ptau" $zkey "$circuit"
}

if [[ $remainder -gt 0 ]]; then
    setup_remainder_inputs="one_remainder two_remainder"
fi

# these need to be exported for the parallel command
export -f setup_layers build_dir ptau_path zkey_arg circuit_path parse_layer_name exitsting_zkey_path
export TESTS_DIR SCRIPTS_DIR LOGS_DIR BUILD_DIR THIS_DIR
export threshold parallelism num_sigs naming_map

printf "
================ RUNNING G16 SETUP FOR ALL LAYERS ================
SEE $LOGS_DIR/layer_\$layer_setup.log
================
"

generate_merkle_tree &
parallel --joblog "$LOGS_DIR/setup_layers.log" setup_layers {} '>' "$LOGS_DIR"/layer_{}_setup.log '2>&1' ::: one two three $setup_remainder_inputs

wait

# ///////////////////////////////////////////////////////
# Move zkeys to test dir.

move_zkey() {
    local _name zkey_path_build zkey_path_save

    parse_layer_name $1 _name
    generated_zkey_path $1 zkey_path
    exitsting_zkey_path $1 zkey_path_save

    if [[ -f "$zkey_path" ]]; then
        mv "$zkey_path" "$zkey_path_save"
    fi
}

# these need to be exported for the parallel command
export -f move_zkey generated_zkey_path

parallel move_zkey ::: one two three $setup_remainder_inputs

# ///////////////////////////////////////////////////////
# Layer 1 & 2 prove in parallel.

# Use GNU's parallel.
# https://www.baeldung.com/linux/bash-for-loop-parallel#4-gnu-parallel-vs-xargs-for-distributing-commands-to-remote-servers
# https://www.gnu.org/software/parallel/parallel_examples.html#example-rewriting-a-for-loop-and-a-while-read-loop

prove_layers_one_two() {
    i=$1 # batch number

    # Re-import these 'cause they don't seem to come through the parallel command.
    . "$THIS_DIR/../scripts/lib/error_handling.sh"
    . "$THIS_DIR/../scripts/lib/cmd_executor.sh"

    local start_index end_index build signals circuit zkey proof

    # Index range of the signature set to be done in this batch.
    start_index=$((i * threshold))
    if [[ $i -eq $((parallelism - 1)) ]]; then
        end_index=$num_sigs
    else
        end_index=$((start_index + threshold)) # not inclusive
    fi

    # Setup layer 1 path variables.
    build_dir 1 build
    signals_path 1 signals
    circuit_path 1 circuit
    zkey_arg 1 zkey

    l1_proof_dir="$build"/batch_"$i"
    if [[ ! -d "$l1_proof_dir" ]]; then
        mkdir -p "$l1_proof_dir"
    fi

    MSG="PREPARING INPUT SIGNALS FILE FOR LAYER 1 CIRCUIT BATCH $i"
    execute npx ts-node "$SCRIPTS_DIR"/input_prep_for_layer_one.ts --poa-input-data "$POA_INPUT_PATH" --write-layer-one-data-to "$signals" --account-start-index $start_index --account-end-index $end_index

    "$SCRIPTS_DIR"/g16_prove.sh -b -B "$build" -p "$l1_proof_dir" $zkey "$circuit" "$signals"
    "$SCRIPTS_DIR"/g16_verify.sh -b -B "$build" -p "$l1_proof_dir" $zkey "$circuit"

    # Setup layer 2 path variables.
    build_dir 2 build
    signals_path 2 signals
    circuit_path 2 circuit
    zkey_arg 2 zkey

    l2_proof_dir="$build"/batch_"$i"
    if [[ ! -d "$l2_proof_dir" ]]; then
        mkdir -p "$l2_proof_dir"
    fi

    MSG="CONVERTING LAYER 1 PROOF TO LAYER 2 INPUT SIGNALS BATCH $i"
    execute python "$SCRIPTS_DIR"/sanitize_groth16_proof.py "$l1_proof_dir"

    MSG="PREPARING INPUT SIGNALS FILE FOR LAYER 2 CIRCUIT BATCH $i"
    execute npx ts-node "$SCRIPTS_DIR"/input_prep_for_layer_two.ts --poa-input-data "$POA_INPUT_PATH" --merkle-root "$MERKLE_ROOT_PATH" --merkle-proofs "$MERKLE_PROOFS_PATH" --layer-one-sanitized-proof "$l1_proof_dir"/sanitized_proof.json --write-layer-two-data-to "$signals" --account-start-index $start_index --account-end-index $end_index

    MSG="RUNNING PROVING SYSTEM FOR LAYER 2 CIRCUIT BATCH $i"
    printf "\n================ $MSG ================\n"

    "$SCRIPTS_DIR"/g16_prove.sh -b -B "$build" -p "$l2_proof_dir" $zkey "$circuit" "$signals"
    "$SCRIPTS_DIR"/g16_verify.sh -b -B "$build" -p "$l1_proof_dir" $zkey "$circuit"

    MSG="CONVERTING LAYER 2 PROOF TO LAYER 3 INPUT SIGNALS"
    execute python "$SCRIPTS_DIR"/sanitize_groth16_proof.py "$l2_proof_dir"
}

# these need to be exported for the parallel command
export -f prove_layers_one_two
export POA_INPUT_PATH MERKLE_ROOT_PATH MERKLE_PROOFS_PATH

printf "
================ PROVING ALL BATCHES OF LAYERS 1 & 2 IN PARALLEL ================
SEE $LOGS_DIR/layers_one_two_prove_batch_\$i.log
OR $LOGS_DIR/layers_one_two_prove.log
================
"

seq 0 $((parallelism - 1)) | parallel --joblog "$LOGS_DIR/layers_one_two_prove.log" prove_layers_one_two {} '>' "$LOGS_DIR"/layers_one_two_prove_batch_{}.log '2>&1'

# ///////////////////////////////////////////////////////
# Layer 3 prove.

# Setup layer 3 path variables.
build_dir 3 build
signals_path 3 signals
circuit_path 3 circuit
zkey_arg 3 zkey

MSG="PREPARING INPUT SIGNALS FILE FOR LAYER THREE CIRCUIT"
execute npx ts-node "$SCRIPTS_DIR"/input_prep_for_layer_three.ts --poa-input-data "$POA_INPUT_PATH" --merkle-root "$MERKLE_ROOT_PATH" --layer-two-sanitized-proof "$build" --multiple-proofs --write-layer-three-data-to "$signals" --blinding-factor $BLINDING_FACTOR

MSG="RUNNING PROVING SYSTEM FOR LAYER THREE CIRCUIT"
printf "\n================ $MSG ================\n"

"$SCRIPTS_DIR"/g16_prove.sh -b -B "$build" $zkey "$circuit" "$signals"

MSG="VERIFYING FINAL PEDERSEN COMMITMENT"
execute npx ts-node "$SCRIPTS_DIR"/pedersen_commitment_checker.ts --layer-three-public-inputs "$build"/public.json --blinding-factor $BLINDING_FACTOR

echo "SUCCESS"
