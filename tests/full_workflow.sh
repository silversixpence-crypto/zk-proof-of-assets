#!/usr/bin/env bash

FULL_WORKFLOW_PATH="$(realpath "${BASH_SOURCE[-1]}")"
FULL_WORKFLOW_DIRECTORY="$(dirname "$FULL_WORKFLOW_PATH")"

. "$FULL_WORKFLOW_DIRECTORY/../scripts/lib/error_handling.sh"
. "$FULL_WORKFLOW_DIRECTORY/../scripts/lib/cmd_executor.sh"

npx ts-node ./tests/generate_test_input.ts --num-sigs 2 --message "message to sign"
npx ts-node ./scripts/input_prep_for_layer_one.ts -s "$FULL_WORKFLOW_DIRECTORY/signatures_2.json" -o "$FULL_WORKFLOW_DIRECTORY/layer_one/input.json" -h "$FULL_WORKFLOW_DIRECTORY/pubkey_x_coords_hash.txt"

"$FULL_WORKFLOW_DIRECTORY"/layer_one/layer_one.sh

BUILD_DIR="$FULL_WORKFLOW_DIRECTORY"/../build/tests/layer_one

X_COORDS_HASH_FRM_PROOF=$(cat "$BUILD_DIR/public.json" | grep -o -E "[0-9]{76}")
X_COORDS_HASH_FRM_SCRIPT=$(cat "$FULL_WORKFLOW_DIRECTORY/pubkey_x_coords_hash.txt")

if [[ $X_COORDS_HASH_FRM_PROOF != $X_COORDS_HASH_FRM_SCRIPT ]]; then
    echo "X-coords hash from layer one proof ($X_COORDS_HASH_FRM_PROOF) is not the same as the one generated from the script ($X_COORDS_HASH_FRM_SCRIPT)"
    exit 1
fi
