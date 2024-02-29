#!/usr/bin/env bash

THIS_FILE_PATH="$(realpath "${BASH_SOURCE[-1]}")"
THIS_DIR="$(dirname "$THIS_FILE_PATH")"

. "$THIS_DIR/../scripts/lib/error_handling.sh"
. "$THIS_DIR/../scripts/lib/cmd_executor.sh"

# ///////////////////////////////////////////////////////
# Variables.

num_sigs=5
anon_set_size=10000
merkle_tree_height=25

threshold=2
parallelism=$((num_sigs / threshold))
remainder=0

if [[ $((parallelism * threshold)) < $num_sigs ]]; then
	remainder=$((num_sigs - parallelism * threshold))
	parallelism=$((parallelism + 1))
fi

printf "
/////////////////////////////////////////////////////////
Initiating test for the following data:

- Number of accounts/signatures:   $num_sigs
- Anonymity set size:              $anon_set_size
- Merkle tree height:              $merkle_tree_height
- Parallelism:                     $parallelism

/////////////////////////////////////////////////////////
"

# ///////////////////////////////////////////////////////
# Constants.

SCRIPTS="$THIS_DIR"/../scripts
BUILD="$THIS_DIR"/../build
TESTS="$THIS_DIR"/"$num_sigs"_sigs
LOGS="$TESTS"/logs
POA_INPUT="$THIS_DIR"/input_data_for_"$num_sigs"_accounts.json
MERKLE_ROOT="$THIS_DIR"/merkle_root.json
MERKLE_PROOFS="$THIS_DIR"/merkle_proofs.json

# ///////////////////////////////////////////////////////
# Create directories.

if [[ ! -d "$BUILD" ]]; then
	mkdir -p "$BUILD"
fi

if [[ ! -d "$TESTS" ]]; then
	mkdir -p "$TESTS"
fi

if [[ ! -d "$LOGS" ]]; then
	mkdir -p "$LOGS"
fi

# ///////////////////////////////////////////////////////
# Layer-specific constants.

L1_BUILD="$BUILD"/tests/layer_one
L1_CIRCUIT="$TESTS"/layer_one.circom
L1_PTAU="$THIS_DIR"/../powersOfTau28_hez_final_26.ptau

L2_BUILD="$BUILD"/tests/layer_two
L2_CIRCUIT="$TESTS"/layer_two.circom
L2_PTAU_PATH="$THIS_DIR"/../powersOfTau28_hez_final_26.ptau
L2_SIGNALS="$TESTS"/layer_two_input.json

L3_BUILD="$BUILD"/tests/layer_three
L3_CIRCUIT_PATH="$TESTS"/layer_three.circom
L3_PTAU_PATH="$THIS_DIR"/../powersOfTau28_hez_final_26.ptau
L3_SIGNALS="$TESTS"/layer_three_input.json

# ///////////////////////////////////////////////////////
# Data generation

MSG="GENERATING TEST CIRCUITS"
execute npx ts-node "$THIS_DIR"/generate_test_circuits.ts --num-sigs $num_sigs --tree-height $merkle_tree_height --parallelism $parallelism

MSG="GENERATING TEST INPUT FOR PROOF OF ASSETS PROTOCOL"
execute npx ts-node "$THIS_DIR"/generate_test_input.ts --num-sigs $num_sigs --message "message to sign"

MSG="GENERATING ANONYMITY SET"
execute npx ts-node "$THIS_DIR"/generate_anon_set.ts --num-addresses $anon_set_size

# Run in parallel to the next commands, 'cause it takes long
(MSG="GENERATING MERKLE TREE FOR ANONYMITY SET, AND MERKLE PROOFS FOR OWNED ADDRESSES" execute npx ts-node "$SCRIPTS"/merkle_tree.ts --anonymity-set "$THIS_DIR"/anonymity_set.json --poa-input-data "$POA_INPUT" --output-dir "$THIS_DIR" --height $merkle_tree_height) &

# ///////////////////////////////////////////////////////
# G16 setup for all layers, in parallel.

# TODO check number of sigs and only do the -b flag if there are more than 10M constraints
(
	printf "\n================ RUNNING G16 SETUP FOR LAYER 1 CIRCUIT (SEE $LOGS/layer_one_setup.log) ================\n" &&
		"$SCRIPTS"/g16_setup.sh -b -B "$L1_BUILD" "$L1_CIRCUIT" "$L1_PTAU" >"$LOGS"/layer_one_setup.log 2>&1
) &

(
	printf "\n================ RUNNING G16 SETUP FOR LAYER 2 CIRCUIT (SEE $LOGS/layer_two_setup.log) ================\n" &&
		"$SCRIPTS"/g16_setup.sh -b -B "$L2_BUILD" "$L2_CIRCUIT" "$L2_PTAU_PATH" >"$LOGS"/layer_two_setup.log 2>&1
) &

(
	printf "\n================ RUNNING G16 SETUP FOR LAYER 3 CIRCUIT (SEE $LOGS/layer_three_setup.log) ================\n" &&
		"$SCRIPTS"/g16_setup.sh -b -B "$L3_BUILD" "$L3_CIRCUIT_PATH" "$L3_PTAU_PATH" >"$LOGS"/layer_three_setup.log 2>&1
)

wait

# ///////////////////////////////////////////////////////
# Layer 1 prove.

# Run provers in parallel using GNU's parallel.
# https://www.baeldung.com/linux/bash-for-loop-parallel#4-gnu-parallel-vs-xargs-for-distributing-commands-to-remote-servers
# https://www.gnu.org/software/parallel/parallel_examples.html#example-rewriting-a-for-loop-and-a-while-read-loop

prove_layer_one() {
	i=$1

	l1_signals_path="$TESTS"/layer_one_input_"$i".json

	if [[ ! -d "$l1_signals_path" ]]; then
		  mkdir -p "$l1_signals_path"
	fi

	start_index=$((i * threshold))
	end_index=$((start_index + threshold)) # not inclusive

	if [[ end_index -gt num_sigs ]]; then
		  end_index=$num_sigs
	fi

	MSG="PREPARING INPUT SIGNALS FILE FOR LAYER 1 CIRCUIT"
	execute npx ts-node "$SCRIPTS"/input_prep_for_layer_one.ts --poa-input-data "$POA_INPUT" --write-layer-one-data-to "$l1_signals_path" --start-index $start_index --end-index $end_index

	"$SCRIPTS"/g16_prove.sh -b -B "$L1_BUILD" "$L1_CIRCUIT" "$l1_signals_path"
}

export -f input_prep_layer_one

seq 0 $((parallelism - 1)) | parallel input_prep_layer_one {} '>' "$LOGS"/layer_one_prove_{}.log 2>&1

exit 0

# ///////////////////////////////////////////////////////
# Layer 2 prove.

MSG="CONVERTING LAYER 1 PROOF TO LAYER 2 INPUT SIGNALS"
execute python "$SCRIPTS"/sanitize_groth16_proof.py "$L1_BUILD"

MSG="PREPARING INPUT SIGNALS FILE FOR LAYER TWO CIRCUIT"
execute npx ts-node "$SCRIPTS"/input_prep_for_layer_two.ts --poa-input-data "$POA_INPUT" --merkle-root "$MERKLE_ROOT" --merkle-proofs "$MERKLE_PROOFS" --layer-one-sanitized-proof "$L1_BUILD"/sanitized_proof.json --write-layer-two-data-to "$L2_SIGNALS"

MSG="RUNNING PROVING SYSTEM FOR LAYER TWO CIRCUIT"
printf "\n================ $MSG ================\n"

"$SCRIPTS"/g16_prove.sh -b -B "$L2_BUILD" "$L2_CIRCUIT" "$L2_SIGNALS"

# ///////////////////////////////////////////////////////
# Layer 3 prove.

MSG="CONVERTING LAYER 2 PROOF TO LAYER 3 INPUT SIGNALS"
execute python "$SCRIPTS"/sanitize_groth16_proof.py "$L2_BUILD"

MSG="PREPARING INPUT SIGNALS FILE FOR LAYER THREE CIRCUIT"
execute npx ts-node "$SCRIPTS"/input_prep_for_layer_three.ts --poa-input-data "$POA_INPUT" --merkle-root "$MERKLE_ROOT" --layer-two-sanitized-proof "$L2_BUILD"/sanitized_proof.json --write-layer-three-data-to "$L3_SIGNALS"

MSG="RUNNING PROVING SYSTEM FOR LAYER THREE CIRCUIT"
printf "\n================ $MSG ================\n"

"$SCRIPTS"/g16_prove.sh -b -B "$L3_BUILD" "$L3_CIRCUIT_PATH" "$L3_SIGNALS"
