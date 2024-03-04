#!/usr/bin/env bash

THIS_FILE_PATH="$(realpath "${BASH_SOURCE[-1]}")"
THIS_DIR="$(dirname "$THIS_FILE_PATH")"

. "$THIS_DIR/../scripts/lib/error_handling.sh"
. "$THIS_DIR/../scripts/lib/cmd_executor.sh"

# ///////////////////////////////////////////////////////
# Variables.

num_sigs=6
anon_set_size=10000
merkle_tree_height=25

threshold=2
parallelism=$((num_sigs / threshold))
remainder=0

if [[ $((parallelism * threshold)) < $num_sigs ]]; then
	remainder=$((num_sigs - parallelism * threshold))
	parallelism=$((parallelism + 1))
fi

if [[ parallelism -eq 1 ]]; then
	num_sigs_per_batch=$num_sigs
else
	num_sigs_per_batch=$threshold
fi

printf "
/////////////////////////////////////////////////////////
Initiating test with the following parameters:

- Number of accounts/signatures:   $num_sigs
- Anonymity set size:              $anon_set_size
- Merkle tree height:              $merkle_tree_height
- Parallelism:                     $parallelism
- Batch size:                      $num_sigs_per_batch

/////////////////////////////////////////////////////////
"

# ///////////////////////////////////////////////////////
# Constants.

SCRIPTS="$THIS_DIR"/../scripts
BUILD="$THIS_DIR"/../build/tests/"$num_sigs"_sigs
TESTS="$THIS_DIR"/"$num_sigs"_sigs
LOGS="$TESTS"/logs
POA_INPUT="$THIS_DIR"/input_data_for_"$num_sigs"_accounts.json
MERKLE_ROOT="$THIS_DIR"/merkle_root.json
MERKLE_PROOFS="$THIS_DIR"/merkle_proofs.json

# ///////////////////////////////////////////////////////
# Create directories.

if [[ ! -d "$TESTS" ]]; then
	mkdir -p "$TESTS"
fi

if [[ ! -d "$LOGS" ]]; then
	mkdir -p "$LOGS"
fi

# ///////////////////////////////////////////////////////
# Layer-specific constants.

L1_BUILD="$BUILD"/layer_one
L1_CIRCUIT="$TESTS"/layer_one.circom
L1_PTAU="$THIS_DIR"/../powersOfTau28_hez_final_26.ptau

L2_BUILD="$BUILD"/layer_two
L2_CIRCUIT="$TESTS"/layer_two.circom
L2_PTAU="$THIS_DIR"/../powersOfTau28_hez_final_26.ptau

L3_BUILD="$BUILD"/layer_three
L3_CIRCUIT="$TESTS"/layer_three.circom
L3_PTAU="$THIS_DIR"/../powersOfTau28_hez_final.ptau
L3_SIGNALS="$TESTS"/layer_three_input.json

# ///////////////////////////////////////////////////////
# Data generation

# MSG="GENERATING TEST CIRCUITS"
# execute npx ts-node "$THIS_DIR"/generate_test_circuits.ts --num-sigs $num_sigs_per_batch --tree-height $merkle_tree_height --parallelism $parallelism --write-circuits-to "$TESTS"

# MSG="GENERATING TEST INPUT FOR PROOF OF ASSETS PROTOCOL"
# execute npx ts-node "$THIS_DIR"/generate_test_input.ts --num-sigs $num_sigs --message "message to sign"

# MSG="GENERATING ANONYMITY SET"
# execute npx ts-node "$THIS_DIR"/generate_anon_set.ts --num-addresses $anon_set_size

# # Run in parallel to the next commands, 'cause it takes long
# (
# 	MSG="GENERATING MERKLE TREE FOR ANONYMITY SET, AND MERKLE PROOFS FOR OWNED ADDRESSES (SEE $LOGS/merkle_tree.log)" \
# 		execute npx ts-node "$SCRIPTS"/merkle_tree.ts \
# 		--anonymity-set "$THIS_DIR"/anonymity_set.json \
# 		--poa-input-data "$POA_INPUT" \
# 		--output-dir "$THIS_DIR" \
# 		--height $merkle_tree_height \
# 		>"$LOGS"/merkle_tree.log
# ) &

# # ///////////////////////////////////////////////////////
# # G16 setup for all layers, in parallel.

# # TODO check number of sigs and only do the -b flag if there are more than 10M constraints
# (
# 	printf "\n================ RUNNING G16 SETUP FOR LAYER 1 CIRCUIT (SEE $LOGS/layer_one_setup.log) ================\n" &&
# 		"$SCRIPTS"/g16_setup.sh -b -B "$L1_BUILD" "$L1_CIRCUIT" "$L1_PTAU" >"$LOGS"/layer_one_setup.log 2>&1
# ) &

# (
# 	printf "\n================ RUNNING G16 SETUP FOR LAYER 2 CIRCUIT (SEE $LOGS/layer_two_setup.log) ================\n" &&
# 		"$SCRIPTS"/g16_setup.sh -b -B "$L2_BUILD" "$L2_CIRCUIT" "$L2_PTAU" >"$LOGS"/layer_two_setup.log 2>&1
# ) &

# (
# 	printf "\n================ RUNNING G16 SETUP FOR LAYER 3 CIRCUIT (SEE $LOGS/layer_three_setup.log) ================\n" &&
# 		"$SCRIPTS"/g16_setup.sh -b -B "$L3_BUILD" "$L3_CIRCUIT" "$L3_PTAU" >"$LOGS"/layer_three_setup.log 2>&1
# )

wait

# ///////////////////////////////////////////////////////
# Layer 1 & 2 prove in parallel.

# Use GNU's parallel.
# https://www.baeldung.com/linux/bash-for-loop-parallel#4-gnu-parallel-vs-xargs-for-distributing-commands-to-remote-servers
# https://www.gnu.org/software/parallel/parallel_examples.html#example-rewriting-a-for-loop-and-a-while-read-loop

prove_layers_one_two() {
	i=$1

	# TODO add some more identifying information to the filename, or batch dir name (like number of sigs)
	l1_signals_path="$TESTS"/layer_one_input_"$i".json
	l1_proof_dir="$L1_BUILD"/batch_"$i"

	l2_signals_path="$TESTS"/layer_two_input_"$i".json
	l2_proof_dir="$L2_BUILD"/batch_"$i"
	# TODO fix python script to look in the right place for proof data, and remove check in layer two prep script that errors when a file is found as opposed to just dirs

	start_index=$((i * threshold))
	if [[ $i -eq $((parallelism - 1)) ]]; then
		end_index=$num_sigs
	else
		end_index=$((start_index + threshold)) # not inclusive
	fi

	MSG="PREPARING INPUT SIGNALS FILE FOR LAYER 1 CIRCUIT BATCH $i"
	execute npx ts-node "$SCRIPTS"/input_prep_for_layer_one.ts --poa-input-data "$POA_INPUT" --write-layer-one-data-to "$l1_signals_path" --account-start-index $start_index --account-end-index $end_index

	"$SCRIPTS"/g16_prove.sh -b -B "$L1_BUILD" -p "$l1_proof_dir" "$L1_CIRCUIT" "$l1_signals_path"

	MSG="CONVERTING LAYER 1 PROOF TO LAYER 2 INPUT SIGNALS BATCH $i"
	execute python "$SCRIPTS"/sanitize_groth16_proof.py "$l1_proof_dir"

	MSG="PREPARING INPUT SIGNALS FILE FOR LAYER 2 CIRCUIT BATCH $i"
	execute npx ts-node "$SCRIPTS"/input_prep_for_layer_two.ts --poa-input-data "$POA_INPUT" --merkle-root "$MERKLE_ROOT" --merkle-proofs "$MERKLE_PROOFS" --layer-one-sanitized-proof "$l1_proof_dir"/sanitized_proof.json --write-layer-two-data-to "$l2_signals_path" --account-start-index $start_index --account-end-index $end_index

	MSG="RUNNING PROVING SYSTEM FOR LAYER 2 CIRCUIT BATCH $i"
	printf "\n================ $MSG ================\n"

	"$SCRIPTS"/g16_prove.sh -b -B "$L2_BUILD" -p "$l2_proof_dir" "$L2_CIRCUIT" "$l2_signals_path"
}

export -f prove_layers_one_two
export -f execute
export TESTS L1_BUILD L1_CIRCUIT L2_BUILD L2_CIRCUIT POA_INPUT SCRIPTS MERKLE_ROOT MERKLE_PROOFS
export threshold parallelism num_sigs

printf "\n================ PROVING ALL BATCHES OF LAYERS 1 & 2 IN PARALLEL (SEE $LOGS/layers_one_two_prove_i.log) ================\n"
seq 0 $((parallelism - 1)) | parallel prove_layers_one_two {} '>' "$LOGS"/layers_one_two_prove_{}.log '2>&1'

exit 0

# ///////////////////////////////////////////////////////
# Layer 3 prove.

MSG="CONVERTING LAYER 2 PROOF TO LAYER 3 INPUT SIGNALS"
execute python "$SCRIPTS"/sanitize_groth16_proof.py "$L2_BUILD"

MSG="PREPARING INPUT SIGNALS FILE FOR LAYER THREE CIRCUIT"
execute npx ts-node "$SCRIPTS"/input_prep_for_layer_three.ts --poa-input-data "$POA_INPUT" --merkle-root "$MERKLE_ROOT" --layer-two-sanitized-proof "$L2_BUILD"/sanitized_proof.json --write-layer-three-data-to "$L3_SIGNALS"

MSG="RUNNING PROVING SYSTEM FOR LAYER THREE CIRCUIT"
printf "\n================ $MSG ================\n"

"$SCRIPTS"/g16_prove.sh -b -B "$L3_BUILD" "$L3_CIRCUIT" "$L3_SIGNALS"
