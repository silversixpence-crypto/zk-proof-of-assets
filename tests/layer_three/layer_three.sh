#!/usr/bin/env bash

# This test verifies 2 signatures using the faster settings for g16_setup.sh & g16_prove.sh

LAYER_THREE_PATH="$(realpath "${BASH_SOURCE[-1]}")"
LAYER_THREE_DIRECTORY="$(dirname "$LAYER_THREE_PATH")"

CIRCUIT_PATH="$LAYER_THREE_DIRECTORY"/layer_three_2_sigs.circom
BUILD_DIR="$LAYER_THREE_DIRECTORY"/../../build/tests/layer_three
PTAU_PATH="$LAYER_THREE_DIRECTORY"/../../powersOfTau28_hez_final_26.ptau
SIGNALS="$LAYER_THREE_DIRECTORY"/input.json

"$LAYER_THREE_DIRECTORY"/../../scripts/g16_setup.sh -b -B "$BUILD_DIR" "$CIRCUIT_PATH" "$PTAU_PATH"
"$LAYER_THREE_DIRECTORY"/../../scripts/g16_prove.sh -b -B "$BUILD_DIR" "$CIRCUIT_PATH" "$SIGNALS"
