#!/usr/bin/env bash

# This test verifies 2 signatures using the slower settings for g16_setup.sh & g16_prove.sh

LAYER_ONE_PATH="$(realpath "${BASH_SOURCE[-1]}")"
LAYER_ONE_DIRECTORY="$(dirname "$LAYER_ONE_PATH")"

CIRCUIT_PATH="$LAYER_ONE_DIRECTORY"/layer_one_2_sigs.circom
BUILD_DIR="$LAYER_ONE_DIRECTORY"/../../build/tests/layer_one
PTAU_PATH="$LAYER_ONE_DIRECTORY"/../../powersOfTau28_hez_final_22.ptau
SIGNALS="$LAYER_ONE_DIRECTORY"/input.json

"$LAYER_ONE_DIRECTORY"/../../scripts/g16_setup.sh -B "$BUILD_DIR" "$CIRCUIT_PATH" "$PTAU_PATH"
"$LAYER_ONE_DIRECTORY"/../../scripts/g16_prove.sh -B "$BUILD_DIR" "$CIRCUIT_PATH" "$SIGNALS"

