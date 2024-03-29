#!/usr/bin/env bash

THIS_FILE_PATH="$(realpath "${BASH_SOURCE[-1]}")"
THIS_DIR="$(dirname "$THIS_FILE_PATH")"

. "$THIS_DIR/../scripts/lib/error_handling.sh"
. "$THIS_DIR/../scripts/lib/cmd_executor.sh"

# ///////////////////////////////////////////////////////
# Variables.

num_sigs=6
anon_set_size=10000
merkle_tree_height=25

threshold=2
parallelism=$((num_sigs / threshold))
remainder=0

if [[ $((parallelism * threshold)) < $num_sigs ]]; then
    remainder=$((num_sigs - parallelism * threshold))
    parallelism=$((parallelism + 1))
fi

if [[ parallelism -eq 1 ]]; then
    num_sigs_per_batch=$num_sigs
else
    num_sigs_per_batch=$threshold
fi

printf "
/////////////////////////////////////////////////////////
Initiating test with the following parameters:

- Number of accounts/signatures:   $num_sigs
- Anonymity set size:              $anon_set_size
- Merkle tree height:              $merkle_tree_height
- Parallelism:                     $parallelism
- Batch size:                      $num_sigs_per_batch

/////////////////////////////////////////////////////////
"

# ///////////////////////////////////////////////////////
# Constants.

IDENTIFIER="$num_sigs"_sigs_"$parallelism"_batches_"$merkle_tree_height"_height

BUILD="$THIS_DIR"/../build/tests/$IDENTIFIER
MERKLE_PROOFS="$THIS_DIR"/merkle_proofs.json
MERKLE_ROOT="$THIS_DIR"/merkle_root.json
POA_INPUT="$THIS_DIR"/input_data_for_"$num_sigs"_accounts.json
SCRIPTS="$THIS_DIR"/../scripts
TESTS="$THIS_DIR"/$IDENTIFIER

LOGS="$TESTS"/logs

BLINDING_FACTOR="4869643893319708471955165214975585939793846505679808910535986866633137979160"

# ///////////////////////////////////////////////////////
# Create directories.

if [[ ! -d "$TESTS" ]]; then
    mkdir -p "$TESTS"
fi

if [[ ! -d "$LOGS" ]]; then
    mkdir -p "$LOGS"
fi

# ///////////////////////////////////////////////////////
# Layer-specific constants.

L1_BUILD="$BUILD"/layer_one
L1_CIRCUIT="$TESTS"/layer_one.circom
L1_PTAU="$THIS_DIR"/../powersOfTau28_hez_final_26.ptau
L1_EXISTING_ZKEY="$TESTS"/layer_one_"$num_sigs"_sigs.zkey
if [[ -f "$L1_EXISTING_ZKEY" ]]; then
    L1_ZKEY_ARG="-Z $L1_EXISTING_ZKEY"
fi

L2_BUILD="$BUILD"/layer_two
L2_CIRCUIT="$TESTS"/layer_two.circom
L2_PTAU="$THIS_DIR"/../powersOfTau28_hez_final_26.ptau
L2_EXISTING_ZKEY="$TESTS"/layer_two_"$num_sigs"_sigs_"$merkle_tree_height"_height.zkey
if [[ -f "$L2_EXISTING_ZKEY" ]]; then
    L2_ZKEY_ARG="-Z $L2_EXISTING_ZKEY"
fi

L3_BUILD="$BUILD"/layer_three
L3_CIRCUIT="$TESTS"/layer_three.circom
L3_PTAU="$THIS_DIR"/../powersOfTau28_hez_final.ptau
L3_SIGNALS="$TESTS"/layer_three_input.json
L3_EXISTING_ZKEY="$TESTS"/layer_three_"$parallelism"_batches.zkey
if [[ -f "$L3_EXISTING_ZKEY" ]]; then
    L3_ZKEY_ARG="-Z $L3_EXISTING_ZKEY"
fi

# ///////////////////////////////////////////////////////
# Data generation

MSG="GENERATING TEST CIRCUITS"
execute npx ts-node "$THIS_DIR"/generate_test_circuits.ts --num-sigs $num_sigs_per_batch --tree-height $merkle_tree_height --parallelism $parallelism --write-circuits-to "$TESTS"

MSG="GENERATING TEST INPUT FOR PROOF OF ASSETS PROTOCOL"
execute npx ts-node "$THIS_DIR"/generate_test_input.ts --num-sigs $num_sigs --message "message to sign"

MSG="GENERATING ANONYMITY SET"
execute npx ts-node "$THIS_DIR"/generate_anon_set.ts --num-addresses $anon_set_size

# Run in parallel to the next commands, 'cause it takes long
(
    MSG="GENERATING MERKLE TREE FOR ANONYMITY SET, AND MERKLE PROOFS FOR OWNED ADDRESSES (SEE $LOGS/merkle_tree.log)" &&
        printf "\n================ $MSG ================ \n" &&
        execute npx ts-node "$SCRIPTS"/merkle_tree.ts \
            --anonymity-set "$THIS_DIR"/anonymity_set.json \
            --poa-input-data "$POA_INPUT" \
            --output-dir "$THIS_DIR" \
            --height $merkle_tree_height \
            >"$LOGS"/merkle_tree.log
) &

# ///////////////////////////////////////////////////////
# G16 setup for all layers, in parallel.

# TODO check number of sigs and only do the -b flag if there are more than 10M constraints
(
    printf "\n================ RUNNING G16 SETUP FOR LAYER 1 CIRCUIT ================\nSEE $LOGS/layer_one_setup.log\n" &&
        "$SCRIPTS"/g16_setup.sh -b -B "$L1_BUILD" -t "$L1_PTAU" $L1_ZKEY_ARG "$L1_CIRCUIT" >"$LOGS"/layer_one_setup.log 2>&1
) &

(
    printf "\n================ RUNNING G16 SETUP FOR LAYER 2 CIRCUIT ================\nSEE $LOGS/layer_two_setup.log\n" &&
        "$SCRIPTS"/g16_setup.sh -b -B "$L2_BUILD" -t "$L2_PTAU" $L2_ZKEY_ARG "$L2_CIRCUIT" >"$LOGS"/layer_two_setup.log 2>&1
) &

(
    printf "\n================ RUNNING G16 SETUP FOR LAYER 3 CIRCUIT ================\nSEE $LOGS/layer_three_setup.log\n" &&
        "$SCRIPTS"/g16_setup.sh -b -B "$L3_BUILD" -t "$L3_PTAU" $L3_ZKEY_ARG "$L3_CIRCUIT" >"$LOGS"/layer_three_setup.log 2>&1
)

wait

# ///////////////////////////////////////////////////////
# Move zkeys to test dir.

l1_zkey_path="$L1_BUILD"/layer_one_final.zkey
if [[ -f "$l1_zkey_path" ]]; then
    mv "$l1_zkey_path" "$L1_EXISTING_ZKEY"
fi

l2_zkey_path="$L2_BUILD"/layer_two_final.zkey
if [[ -f "$l2_zkey_path" ]]; then
    mv "$l2_zkey_path" "$L2_EXISTING_ZKEY"
fi

l3_zkey_path="$L3_BUILD"/layer_three_final.zkey
if [[ -f "$l3_zkey_path" ]]; then
    mv "$l3_zkey_path" "$L3_EXISTING_ZKEY"
fi

# ///////////////////////////////////////////////////////
# Layer 1 & 2 prove in parallel.

# Use GNU's parallel.
# https://www.baeldung.com/linux/bash-for-loop-parallel#4-gnu-parallel-vs-xargs-for-distributing-commands-to-remote-servers
# https://www.gnu.org/software/parallel/parallel_examples.html#example-rewriting-a-for-loop-and-a-while-read-loop

prove_layers_one_two() {
    i=$1

    . "$THIS_DIR/../scripts/lib/error_handling.sh"
    . "$THIS_DIR/../scripts/lib/cmd_executor.sh"

    l1_signals_path="$TESTS"/layer_one_input_"$i".json
    l1_proof_dir="$L1_BUILD"/batch_"$i"
    if [[ ! -d "$l1_proof_dir" ]]; then
        mkdir -p "$l1_proof_dir"
    fi

    l2_signals_path="$TESTS"/layer_two_input_"$i".json
    l2_proof_dir="$L2_BUILD"/batch_"$i"
    if [[ ! -d "$l2_proof_dir" ]]; then
        mkdir -p "$l2_proof_dir"
    fi

    start_index=$((i * threshold))
    if [[ $i -eq $((parallelism - 1)) ]]; then
        end_index=$num_sigs
    else
        end_index=$((start_index + threshold)) # not inclusive
    fi

    MSG="PREPARING INPUT SIGNALS FILE FOR LAYER 1 CIRCUIT BATCH $i"
    execute npx ts-node "$SCRIPTS"/input_prep_for_layer_one.ts --poa-input-data "$POA_INPUT" --write-layer-one-data-to "$l1_signals_path" --account-start-index $start_index --account-end-index $end_index

    "$SCRIPTS"/g16_prove.sh -b -B "$L1_BUILD" -p "$l1_proof_dir" $L1_ZKEY_ARG "$L1_CIRCUIT" "$l1_signals_path"

    MSG="CONVERTING LAYER 1 PROOF TO LAYER 2 INPUT SIGNALS BATCH $i"
    execute python "$SCRIPTS"/sanitize_groth16_proof.py "$l1_proof_dir"

    MSG="PREPARING INPUT SIGNALS FILE FOR LAYER 2 CIRCUIT BATCH $i"
    execute npx ts-node "$SCRIPTS"/input_prep_for_layer_two.ts --poa-input-data "$POA_INPUT" --merkle-root "$MERKLE_ROOT" --merkle-proofs "$MERKLE_PROOFS" --layer-one-sanitized-proof "$l1_proof_dir"/sanitized_proof.json --write-layer-two-data-to "$l2_signals_path" --account-start-index $start_index --account-end-index $end_index

    MSG="RUNNING PROVING SYSTEM FOR LAYER 2 CIRCUIT BATCH $i"
    printf "\n================ $MSG ================\n"

    "$SCRIPTS"/g16_prove.sh -b -B "$L2_BUILD" -p "$l2_proof_dir" $L2_ZKEY_ARG "$L2_CIRCUIT" "$l2_signals_path"

    MSG="CONVERTING LAYER 2 PROOF TO LAYER 3 INPUT SIGNALS"
    execute python "$SCRIPTS"/sanitize_groth16_proof.py "$l2_proof_dir"
}

# these need to be exported for the parallel command
export -f prove_layers_one_two
export TESTS L1_BUILD L1_CIRCUIT L1_ZKEY_ARG L2_BUILD L2_CIRCUIT L2_ZKEY_ARG POA_INPUT SCRIPTS MERKLE_ROOT MERKLE_PROOFS THIS_DIR
export threshold parallelism num_sigs

printf "\n================ PROVING ALL BATCHES OF LAYERS 1 & 2 IN PARALLEL ================\nSEE $LOGS/layers_one_two_prove_batch_\$i.log\n"
seq 0 $((parallelism - 1)) | parallel --joblog "$LOGS/layers_one_two_prove.log" prove_layers_one_two {} '>' "$LOGS"/layers_one_two_prove_batch_{}.log '2>&1'

# ///////////////////////////////////////////////////////
# Layer 3 prove.

MSG="PREPARING INPUT SIGNALS FILE FOR LAYER THREE CIRCUIT"
execute npx ts-node "$SCRIPTS"/input_prep_for_layer_three.ts --poa-input-data "$POA_INPUT" --merkle-root "$MERKLE_ROOT" --layer-two-sanitized-proof "$L2_BUILD" --multiple-proofs --write-layer-three-data-to "$L3_SIGNALS" --blinding-factor $BLINDING_FACTOR

MSG="RUNNING PROVING SYSTEM FOR LAYER THREE CIRCUIT"
printf "\n================ $MSG ================\n"

"$SCRIPTS"/g16_prove.sh -b -B "$L3_BUILD" $L3_ZKEY_ARG  "$L3_CIRCUIT" "$L3_SIGNALS"

MSG="VERIFYING FINAL PEDERSEN COMMITMENT"
execute npx ts-node "$SCRIPTS"/pedersen_commitment_checker.ts --layer-three-public-inputs "$L3_BUILD"/public.json --blinding-factor $BLINDING_FACTOR

echo "SUCCESS"
