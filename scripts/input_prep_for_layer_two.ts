/**
Format data for use in layer 2 circuit.

This script takes
1. the output of ecdsa_sigs_parser.ts: `ProofOfAssetsInputFileShape`
2. merkle root (`bigint`) & proofs (`Proofs`) from merkle_tree.rs
3. layer 1 proof (after sanitization with sanitize_groth16_proof.py): `Groth16ProofAsInput`
and converts it to the format required by the layer 2 circuit: `LayerTwoInputFileShape`

Note that the output of ecdsa_sigs_parser.ts contains all the signatures, but
we only want to take a portion of them for each batch. We can choose which
portion via the index options in the CLI.
**/

import { Point, CURVE } from '@noble/secp256k1';
import { jsonReviver } from "./lib/json_serde";
import { bigint_to_array, bigint_to_Uint8Array, Uint8Array_to_bigint } from "./lib/utils";
import {
    EcdsaStarSignature,
    ProofOfAssetsInputFileShape,
    Groth16ProofAsInput,
    AccountAttestation,
    Proofs,
    Leaf
} from "./lib/interfaces";

const fs = require("fs");
const circomlibjs = require("circomlibjs");
const path = require("path");

interface LayerTwoInputFileShape extends Omit<Groth16ProofAsInput, "pubInput"> {
    pubkey_x_coord_hash: string,
    pubkey: bigint[][][],
    leaf_addresses: bigint[],
    leaf_balances: bigint[],
    merkle_root: bigint,
    path_elements: bigint[][],
    path_indices: number[][],
}

// =========================================================
// Hashing pubkeys.

// Wrapper around poseidon implementation that allows any length input.
// Out the box it supports a max of 16.
async function poseidonSponge(inputs: bigint[]): Promise<bigint> {
    var round_length_max = 16;
    var num_rounds = Math.floor(inputs.length / round_length_max);
    var out_length = 1;
    var round_length = round_length_max;
    var last_round_length = round_length_max;
    var hash_out: any = 0n;

    if (inputs.length % round_length_max > 0) {
        num_rounds++;
        last_round_length = inputs.length % round_length_max;
    }

    const poseidon = await circomlibjs.buildPoseidonOpt();

    for (var i = 0; i < num_rounds; i++) {
        var intermediate_inputs: bigint[] = [];
        var initial_state: any = hash_out;

        if (i === num_rounds - 1) {
            out_length = 2;
            round_length = last_round_length;
        }

        for (var j = 0; j < round_length; j++) {
            intermediate_inputs[j] = inputs[i * round_length + j];
        }

        hash_out = await poseidon(intermediate_inputs, initial_state, out_length);
    }

    const field = poseidon.F;
    return await field.toObject(hash_out[1]);
}

async function hash_x_coords(x_coords: bigint[]): Promise<string> {
    let hash: bigint = await poseidonSponge(x_coords);
    return hash.toString();
}

async function write_pubkey_x_coords_hash(pubkeys: Point[], output_path: String): Promise<string> {
    let x_coords = pubkeys.map(pubkey => bigint_to_array(64, 4, pubkey.x)).flat();
    let hash = await hash_x_coords(x_coords);

    fs.writeFileSync(output_path, hash);

    return hash;
}

// =========================================================
// Input signal builder for the circuit.

function construct_input(proof_data: Groth16ProofAsInput, x_coords_hash: string, accountAttestations: AccountAttestation[], merkle_root: bigint, merkle_proofs: Proofs): LayerTwoInputFileShape {
    var { pubInput, ...other_data } = proof_data;

    var layer_two_input: LayerTwoInputFileShape = {
        ...other_data,
        pubkey_x_coord_hash: x_coords_hash,
        pubkey: accountAttestations.map(a => [
            bigint_to_array(64, 4, a.signature.pubkey.x),
            bigint_to_array(64, 4, a.signature.pubkey.y)
        ]),
        leaf_addresses: accountAttestations.map(a => a.accountData.address),
        leaf_balances: accountAttestations.map(a => a.accountData.balance),
        merkle_root,
        path_elements: merkle_proofs.path_elements,
        path_indices: merkle_proofs.path_indices,
    };

    return layer_two_input;
}

// =========================================================
// Checks.

// accountAttestations & merkle_leaves come from 2 different files so it's not guaranteed that
// each element of the one corresponds to the other. This is checked here. We also check
// that the addresses are in ascending order, which is required by the circuit so that
// the prover cannot do a double-spend attack.
function check_address_ordering(accountAttestations: AccountAttestation[], merkle_leaves: Leaf[]) {
    if (accountAttestations.length != merkle_leaves.length) {
        throw new Error(`Length of input data array ${accountAttestations.length} should equal length of merkle proofs array ${merkle_leaves.length}`);
    }

    for (let i = 0; i < accountAttestations.length; i++) {
        let addr_input: bigint = accountAttestations[i].accountData.address;
        let addr_merkle: bigint = merkle_leaves[i].address;

        if (addr_input != addr_merkle) {
            throw new Error(`[i = ${i}] Address in input data array ${addr_input} should equal address in merkle proofs array ${addr_merkle}`);
        }

        // Check ascending order.
        if (i > 0) {
            let addr_merkle_prev = merkle_leaves[i - 1].address;

            if (addr_merkle < addr_merkle_prev) {
                throw new Error(`Addresses must be in ascending order, but address at i=${i} (${addr_merkle}) is less than the previous address (${addr_merkle_prev})`);
            } else if (addr_merkle === addr_merkle_prev) {
                throw new Error(`Cannot have duplicate addresses, but address at i=${i} (${addr_merkle}) is the same as the previous address (${addr_merkle_prev})`);
            }
        }
    }
}

// =========================================================
// Main execution flow.

var argv = require('minimist')(process.argv.slice(2), {
    alias: {
        poa_input_data_path: ['poa-input-data', 'i'],
        merkle_root_path: ['merkle-root', 't'],
        merkle_proofs_path: ['merkle-proofs', 'p'],
        x_coords_hash_path: ['write-x-coords-hash-to', 'h'],
        layer_one_sanitized_proof_path: ['layer-one-sanitized-proof', 'd'],
        layer_two_input_path: ['write-layer-two-data-to', 'o'],
        account_start_index: ['account-start-index', 's'],
        account_end_index: ['account-end-index', 'e'],
    },
    default: {
        poa_input_data_path: path.join(__dirname, "../tests/input_data_for_32_accounts.json"),
        merkle_root_path: path.join(__dirname, "../tests/merkle_root.json"),
        merkle_proofs_path: path.join(__dirname, "../tests/merkle_proofs.json"),
        x_coords_hash_path: path.join(__dirname, "../tests/pubkey_x_coords_hash.txt"),
        layer_one_sanitized_proof_path: path.join(__dirname, "../build/tests/layer_one/sanitized_proof.json"),
        layer_two_input_path: path.join(__dirname, "../tests/layer_two/input.json"),
        account_start_index: 0,
        account_end_index: -1,
    }
});

let input_data_path = argv.poa_input_data_path;
let merkle_root_path = argv.merkle_root_path;
let merkle_proofs_path = argv.merkle_proofs_path;
let x_coords_hash_path = argv.x_coords_hash_path;
let layer_one_sanitized_proof_path = argv.layer_one_sanitized_proof_path;
let layer_two_input_path = argv.layer_two_input_path;
let start_index = argv.account_start_index;
let end_index = argv.account_end_index;

let input_data_raw = fs.readFileSync(input_data_path);
let input_data: ProofOfAssetsInputFileShape = JSON.parse(input_data_raw, jsonReviver);

if (end_index === -1) {
    end_index = input_data.accountAttestations.length;
}

if (start_index >= end_index) {
    throw new Error(`start_index ${start_index} must be less than end_index ${end_index}`);
}

let accountAttestations = input_data.accountAttestations.slice(start_index, end_index);

write_pubkey_x_coords_hash(accountAttestations.map(w => w.signature.pubkey), x_coords_hash_path)
    .then(x_coords_hash => {
        let merkle_root_raw = fs.readFileSync(merkle_root_path);
        let merkle_root: bigint = JSON.parse(merkle_root_raw, jsonReviver);

        let merkle_proofs_raw = fs.readFileSync(merkle_proofs_path);
        let merkle_proofs: Proofs = JSON.parse(merkle_proofs_raw, jsonReviver);

        let merkle_proofs_slice: Proofs = {
            leaves: merkle_proofs.leaves.slice(start_index, end_index),
            path_elements: merkle_proofs.path_elements.slice(start_index, end_index),
            path_indices: merkle_proofs.path_indices.slice(start_index, end_index),
        }

        var proof_data_raw = fs.readFileSync(layer_one_sanitized_proof_path);
        var proof_data: Groth16ProofAsInput = JSON.parse(proof_data_raw, jsonReviver);

        check_address_ordering(accountAttestations, merkle_proofs_slice.leaves);

        var layer_two_input: LayerTwoInputFileShape = construct_input(proof_data, x_coords_hash, accountAttestations, merkle_root, merkle_proofs_slice);

        const json_out = JSON.stringify(
            layer_two_input,
            (key, value) => typeof value === "bigint" ? value.toString() : value,
            2
        );

        fs.writeFileSync(layer_two_input_path, json_out);
    });
