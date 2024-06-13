#!/usr/bin/env bash

############################################
# Constants.

TEST_FILE_PATH="$(realpath "${BASH_SOURCE[-1]}")"
TEST_DIR="$(dirname "$TEST_FILE_PATH")"

ANON_SET_SIZE=10
NUM_SIGS=1
BLINDING_FACTOR=2

SCRIPTS_DIR="$TEST_DIR/../scripts"
BUILD_DIR="$TEST_DIR"/1_sigs_1_batches_5_height

############################################

npx ts-node "$TEST_DIR"/generate_anon_set.ts --num-addresses $ANON_SET_SIZE
npx ts-node "$TEST_DIR"/generate_ecdsa_signatures.ts --num-sigs $NUM_SIGS -m "message to sign"

signatures=signatures_"$NUM_SIGS".json
anon_set=anonymity_set_"$ANON_SET_SIZE".csv

mv "$TEST_DIR"/$signatures "$BUILD_DIR"
mv "$TEST_DIR"/$anon_set "$BUILD_DIR"

"$SCRIPTS_DIR"/full_workflow.sh \
              -s \
              -p powersOfTau28_hez_final_26.ptau \
              "$BUILD_DIR"/$signatures \
              "$BUILD_DIR"/$anon_set \
              $BLINDING_FACTOR
