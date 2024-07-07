#!/usr/bin/env bash

############################################
# Constants.

TEST_FILE_PATH="$(realpath "${BASH_SOURCE[-1]}")"
TEST_DIR="$(dirname "$TEST_FILE_PATH")"
SCRIPTS_DIR="$TEST_DIR"/../scripts
SOURCE_DIR="$TEST_DIR"/..

# (2^155 - 19) / 167
BLINDING_FACTOR=273484587823896504154881143846609846492502347

NUM_SIGS=7
BATCH_SIZE=3
ANON_SET_SIZE=10600

height=$(echo "2 + l($ANON_SET_SIZE)/l(2)" | bc -l | sed "s/\.[0-9]*//")

output=$(python "$SCRIPTS_DIR"/batch_size_optimizooor.py $NUM_SIGS $BATCH_SIZE)
num_sigs_per_batch=$(echo $output | grep -o -e "[0-9]*" | sed -n 1p)
parallelism=$((NUM_SIGS / num_sigs_per_batch))
if [[ $remainder -gt 0 ]]; then
    parallelism=$((parallelism + 1))
fi

BUILD_DIR="$TEST_DIR"/"$NUM_SIGS"_sigs_"$parallelism"_batches_"$height"_height

############################################

if [[ ! -d "$BUILD_DIR" ]]; then
    mkdir -p "$BUILD_DIR"
fi

npx ts-node "$TEST_DIR"/generate_anon_set.ts --num-addresses $ANON_SET_SIZE
npx ts-node "$TEST_DIR"/generate_ecdsa_signatures.ts --num-sigs $NUM_SIGS -m "message to sign"

signatures=signatures_"$NUM_SIGS".json
anon_set=anonymity_set_"$ANON_SET_SIZE".csv

mv "$TEST_DIR"/$signatures "$BUILD_DIR"
mv "$TEST_DIR"/$anon_set "$BUILD_DIR"

"$SCRIPTS_DIR"/full_workflow.sh \
              -s \
              -b "$BATCH_SIZE" \
              -p "$SOURCE_DIR"/powersOfTau28_hez_final.ptau \
              -B "$TEST_DIR" \
              "$BUILD_DIR"/$signatures \
              "$BUILD_DIR"/$anon_set \
              $BLINDING_FACTOR
