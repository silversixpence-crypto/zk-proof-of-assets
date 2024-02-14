#!/usr/bin/env bash

FULL_WORKFLOW_PATH="$(realpath "${BASH_SOURCE[-1]}")"
FULL_WORKFLOW_DIRECTORY="$(dirname "$FULL_WORKFLOW_PATH")"

npx ts-node ./tests/generate_ecdsa_signatures.ts -n 2 -m "message to sign"
npx ts-node ./scripts/input_prep_for_layer_one.ts -i "$FULL_WORKFLOW_DIRECTORY/signatures_2.json" -o "$FULL_WORKFLOW_DIRECTORY/layer_one/input.json"

"$FULL_WORKFLOW_DIRECTORY"/layer_one/layer_one.sh
