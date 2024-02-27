#!/usr/bin/env bash

THIS_FILE_PATH="$(realpath "${BASH_SOURCE[-1]}")"
THIS_DIR="$(dirname "$THIS_FILE_PATH")"

. "$THIS_DIR/../scripts/lib/error_handling.sh"
. "$THIS_DIR/../scripts/lib/cmd_executor.sh"

NUM_SIGS=2
ANON_SET_SIZE=10000
MERKLE_TREE_HEIGHT=25
PARALELLISM=1

SCRIPTS="$THIS_DIR"/../scripts
BUILD_DIR="$THIS_DIR"/../build
TESTS="$THIS_DIR"/"$NUM_SIGS"_sigs
POA_INPUT="$THIS_DIR"/input_data_for_"$NUM_SIGS"_accounts.json
MERKLE_ROOT="$THIS_DIR"/merkle_root.json
MERKLE_PROOFS="$THIS_DIR"/merkle_proofs.json

printf "
/////////////////////////////////////////////////////////
Initiating test for the following data:

- Number of accounts/signatures:   $NUM_SIGS
- Anonymity set size:              $ANON_SET_SIZE
- Merkle tree height:              $MERKLE_TREE_HEIGHT
- Parallelism:                     $PARALELLISM

/////////////////////////////////////////////////////////
"

set -x

# ///////////////////////////////////////////////////////
# Data generation

MSG="GENERATING TEST CIRCUITS"
execute npx ts-node "$THIS_DIR"/generate_test_circuits.ts --num-sigs $NUM_SIGS --tree-height $MERKLE_TREE_HEIGHT --parallelism $PARALELLISM

MSG="GENERATING TEST INPUT FOR PROOF OF ASSETS PROTOCOL"
execute npx ts-node "$THIS_DIR"/generate_test_input.ts --num-sigs $NUM_SIGS --message "message to sign"

MSG="GENERATING ANONYMITY SET"
execute npx ts-node "$THIS_DIR"/generate_anon_set.ts --num-addresses $ANON_SET_SIZE

MSG="GENERATING MERKLE TREE FOR ANONYMITY SET, AND MERKLE PROOFS FOR OWNED ADDRESSES"
execute npx ts-node "$SCRIPTS"/merkle_tree.ts --anonymity-set "$THIS_DIR"/anonymity_set.json --poa-input-data "$POA_INPUT" --output-dir "$THIS_DIR" --height $MERKLE_TREE_HEIGHT

# ///////////////////////////////////////////////////////
# Layer 1

L1_BUILD="$BUILD_DIR"/tests/layer_one
L1_CIRCUIT_PATH="$TESTS"/layer_one.circom
L1_PTAU_PATH="$THIS_DIR"/../powersOfTau28_hez_final_26.ptau
L1_SIGNALS="$TESTS"/layer_one_input.json

MSG="PREPARING INPUT SIGNALS FILE FOR LAYER 1 CIRCUIT"
execute npx ts-node "$SCRIPTS"/input_prep_for_layer_one.ts --poa-input-data "$POA_INPUT" --write-layer-one-data-to "$L1_SIGNALS"

MSG="RUNNING PROVING SYSTEM FOR LAYER 1 CIRCUIT"
printf "\n================ $MSG ================\n"

# TODO check number of sigs and only do the -b flag if there are more than 10M constraints
"$SCRIPTS"/g16_setup.sh -b -B "$L1_BUILD" "$L1_CIRCUIT_PATH" "$L1_PTAU_PATH"
"$SCRIPTS"/g16_prove.sh -b -B "$L1_BUILD" "$L1_CIRCUIT_PATH" "$L1_SIGNALS"

# ///////////////////////////////////////////////////////
# Layer 2

L2_BUILD="$BUILD_DIR"/tests/layer_two
L2_CIRCUIT_PATH="$TESTS"/layer_two.circom
L2_PTAU_PATH="$THIS_DIR"/../powersOfTau28_hez_final_26.ptau
L2_SIGNALS="$TESTS"/layer_two_input.json

MSG="CONVERTING LAYER 1 PROOF TO LAYER 2 INPUT SIGNALS"
execute python "$SCRIPTS"/sanitize_groth16_proof.py "$L1_BUILD"

MSG="PREPARING INPUT SIGNALS FILE FOR LAYER TWO CIRCUIT"
execute npx ts-node "$SCRIPTS"/input_prep_for_layer_two.ts --poa-input-data "$POA_INPUT" --merkle-root "$MERKLE_ROOT" --merkle-proofs "$MERKLE_PROOFS" --layer-one-sanitized-proof "$L1_BUILD"/sanitized_proof.json --write-layer-two-data-to "$L2_SIGNALS"

MSG="RUNNING PROVING SYSTEM FOR LAYER TWO CIRCUIT"
printf "\n================ $MSG ================\n"

"$SCRIPTS"/g16_setup.sh -b -B "$L2_BUILD" "$L2_CIRCUIT_PATH" "$L2_PTAU_PATH"
"$SCRIPTS"/g16_prove.sh -b -B "$L2_BUILD" "$L2_CIRCUIT_PATH" "$L2_SIGNALS"

# ///////////////////////////////////////////////////////
# Layer 3

L3_BUILD="$BUILD_DIR"/tests/layer_three
L3_CIRCUIT_PATH="$TESTS"/layer_three.circom
L3_PTAU_PATH="$THIS_DIR"/../powersOfTau28_hez_final_26.ptau
L3_SIGNALS="$TESTS"/layer_three_input.json

MSG="CONVERTING LAYER 2 PROOF TO LAYER 3 INPUT SIGNALS"
execute python "$SCRIPTS"/sanitize_groth16_proof.py "$L2_BUILD"

MSG="PREPARING INPUT SIGNALS FILE FOR LAYER THREE CIRCUIT"
execute npx ts-node "$SCRIPTS"/input_prep_for_layer_three.ts --poa-input-data "$POA_INPUT" --merkle-root "$MERKLE_ROOT" --layer-two-sanitized-proof "$L2_BUILD"/sanitized_proof.json --write-layer-three-data-to "$L3_SIGNALS"

MSG="RUNNING PROVING SYSTEM FOR LAYER THREE CIRCUIT"
printf "\n================ $MSG ================\n"

"$SCRIPTS"/g16_setup.sh -b -B "$L3_BUILD" "$L3_CIRCUIT_PATH" "$L3_PTAU_PATH"
"$SCRIPTS"/g16_prove.sh -b -B "$L3_BUILD" "$L3_CIRCUIT_PATH" "$L3_SIGNALS"

# ///////////////////////////////////////////////////////
# Some constraints data

# Constraints for layer one circuit with 2 sigs (-b flag):
#   non-linear constraints: 1932908
#   linear constraints: 161762

# Constraints for layer one circuit with 37 sigs (-b flag):
#   non-linear constraints: 17535746
#   linear constraints: 1079817

# Constraints for layer one circuit with 128 sigs (no -b flag):
#   non-linear constraints: 58099005
#   linear constraints: 0
