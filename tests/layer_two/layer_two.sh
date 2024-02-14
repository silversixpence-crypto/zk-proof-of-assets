#!/usr/bin/env bash

# This test verifies 2 signatures using the slower settings for g16_setup.sh & g16_prove.sh

LAYER_TWO_PATH="$(realpath "${BASH_SOURCE[-1]}")"
LAYER_TWO_DIRECTORY="$(dirname "$LAYER_TWO_PATH")"

CIRCUIT_PATH="$LAYER_TWO_DIRECTORY"/layer_two_2_sigs.circom
BUILD_DIR="$LAYER_TWO_DIRECTORY"/../../build/tests/layer_two
PTAU_PATH="$LAYER_TWO_DIRECTORY"/../../powersOfTau28_hez_final_26.ptau
SIGNALS="$LAYER_TWO_DIRECTORY"/input.json

"$LAYER_TWO_DIRECTORY"/../../scripts/g16_setup.sh -b -B "$BUILD_DIR" "$CIRCUIT_PATH" "$PTAU_PATH"
"$LAYER_TWO_DIRECTORY"/../../scripts/g16_prove.sh -b -B "$BUILD_DIR" "$CIRCUIT_PATH" "$SIGNALS"
