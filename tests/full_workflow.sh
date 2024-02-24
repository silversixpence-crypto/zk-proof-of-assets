#!/usr/bin/env bash

FULL_WORKFLOW_PATH="$(realpath "${BASH_SOURCE[-1]}")"
FULL_WORKFLOW_DIRECTORY="$(dirname "$FULL_WORKFLOW_PATH")"

. "$FULL_WORKFLOW_DIRECTORY/../scripts/lib/error_handling.sh"
. "$FULL_WORKFLOW_DIRECTORY/../scripts/lib/cmd_executor.sh"

SCRIPTS="$FULL_WORKFLOW_DIRECTORY"/../scripts
TESTS="$FULL_WORKFLOW_DIRECTORY"/../tests
BUILD="$FULL_WORKFLOW_DIRECTORY"/../build
POA_INPUT="$FULL_WORKFLOW_DIRECTORY/input_data_for_2_wallets.json"
MERKLE_ROOT="$TESTS"/merkle_root.json
MERKLE_PROOFS="$TESTS"/merkle_proofs.json

ANON_SET_SIZE=100
MERKLE_TREE_HEIGHT=25

MSG="GENERATING TEST INPUT FOR PROOF OF ASSETS PROTOCOL"
execute npx ts-node "$TESTS"/generate_test_input.ts --num-sigs 2 --message "message to sign"

MSG="GENERATING ANONYMITY SET of size $ANON_SET_SIZE"
execute npx ts-node "$TESTS"/generate_anon_set.ts --num-addresses $ANON_SET_SIZE

MSG="GENERATING MERKLE TREE FOR ANONYMITY SET (HEIGHT $MERKLE_TREE_HEIGHT), AND MERKLE PROOFS FOR OWNED ADDRESSES"
execute npx ts-node "$SCRIPTS"/merkle_tree.ts  --anonymity-set "$TESTS"/anonymity_set.json --poa-input-data "$POA_INPUT" --output-dir "$TESTS" --height $MERKLE_TREE_HEIGHT

MSG="PREPARING INPUT SIGNALS FILE FOR LAYER ONE CIRCUIT"
execute npx ts-node "$SCRIPTS"/input_prep_for_layer_one.ts --poa-input-data "$POA_INPUT" --write-layer-one-data-to "$TESTS"/layer_one/input.json

MSG="RUNNING PROVING SYSTEM FOR LAYER ONE CIRCUIT"
printf "\n================ $MSG ================\n"
"$TESTS"/layer_one/layer_one.sh

MSG="CONVERTING LAYER ONE PROOF TO LAYER TWO INPUT SIGNALS"
execute python "$SCRIPTS"/sanitize_groth16_proof.py "$BUILD"/tests/layer_one

MSG="PREPARING INPUT SIGNALS FILE FOR LAYER TWO CIRCUIT"
npx ts-node "$SCRIPTS"/input_prep_for_layer_two.ts --poa-input-data "$POA_INPUT" --merkle-root "$MERKLE_ROOT" --merkle-proofs "$MERKLE_PROOFS" --layer-one-sanitized-proof "$BUILD"/tests/layer_one/sanitized_proof.json --write-layer-two-data-to "$TESTS"/layer_two/input.json

MSG="RUNNING PROVING SYSTEM FOR LAYER TWO CIRCUIT"
printf "\n================ $MSG ================\n"
"$TESTS"/layer_two/layer_two.sh

MSG="CONVERTING LAYER TWO PROOF TO LAYER THREE INPUT SIGNALS"
execute python "$SCRIPTS"/sanitize_groth16_proof.py "$BUILD"/tests/layer_two

MSG="PREPARING INPUT SIGNALS FILE FOR LAYER THREE CIRCUIT"
npx ts-node "$SCRIPTS"/input_prep_for_layer_three.ts --poa-input-data "$POA_INPUT" --merkle-root "$MERKLE_ROOT" --layer-two-sanitized-proof "$BUILD"/tests/layer_two/sanitized_proof.json --write-layer-three-data-to "$TESTS"/layer_three/input.json

MSG="RUNNING PROVING SYSTEM FOR LAYER THREE CIRCUIT"
printf "\n================ $MSG ================\n"
"$TESTS"/layer_three/layer_three.sh
