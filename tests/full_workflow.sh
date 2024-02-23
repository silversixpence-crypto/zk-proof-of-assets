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

npx ts-node "$TESTS"/generate_test_input.ts --num-sigs 2 --message "message to sign"
npx ts-node "$TESTS"/generate_anon_set.ts --num-addresses 100
npx ts-node "$SCRIPTS"/merkle_tree.ts  --anonymity-set "$TESTS"/anonymity_set.json --poa-input-data "$POA_INPUT" --output-dir "$TESTS" --depth 25

npx ts-node "$SCRIPTS"/input_prep_for_layer_one.ts --poa-input-data "$POA_INPUT" --write-layer-one-data-to "$TESTS"/layer_one/input.json

"$TESTS"/layer_one/layer_one.sh

python "$SCRIPTS"/sanitize_groth16_proof.py "$BUILD"/tests/layer_one
npx ts-node "$SCRIPTS"/input_prep_for_layer_two.ts --poa-input-data "$POA_INPUT" --merkle-root "$MERKLE_ROOT" --merkle-proofs "$MERKLE_PROOFS" --layer-one-proof-dir "$BUILD"/tests/layer_one/sanitized_proof.json --write-layer-two-data-to "$TESTS"/layer_two/input.json

"$TESTS"/layer_two/layer_two.sh
