import { Point, CURVE } from '@noble/secp256k1';
import { jsonReviver } from "./lib/json_serde";
import { Signature, ProofOfAssetsInputFileShape, Groth16ProofAsInput, AccountData, Proofs } from "./lib/interfaces";
import { bigint_to_array, bigint_to_Uint8Array } from "./lib/utils";

const fs = require('fs');
const circomlibjs = require("circomlibjs");
const path = require('path');

interface LayerTwoInputFileShape extends Omit<Groth16ProofAsInput, 'pubInput'> {
    pubkey_x_coord_hash: string,
    pubkey: bigint[][][],
    leaf_addresses: bigint[],
    leaf_balances: bigint[],
    merkle_root: bigint,
    path_elements: bigint[][],
    path_indices: number[][],
}

async function hash_x_coords(x_coords: bigint[]) {
    const poseidon = await circomlibjs.buildPoseidon();
    const F = poseidon.F; // poseidon finite field

    let poseidonRes = await poseidon(x_coords);
    let hash = await F.toObject(poseidonRes);

    return hash.toString();
}

async function write_pubkey_x_coords_hash(pubkeys: Point[], output_path: String): Promise<string> {
    let x_coords = pubkeys.map(pubkey => bigint_to_array(64, 4, pubkey.x)).flat();
    let hash = await hash_x_coords(x_coords);

    fs.writeFileSync(output_path, hash);

    return hash;
}

function construct_input(proof_data: Groth16ProofAsInput, x_coords_hash: string, account_data: AccountData[], merkle_root: bigint, merkle_proofs: Proofs): LayerTwoInputFileShape {
    var { pubInput, ...other_data } = proof_data;

    var layer_two_input: LayerTwoInputFileShape = {
        ...other_data,
        pubkey_x_coord_hash: x_coords_hash,
        pubkey: account_data.map(a => [
            bigint_to_array(64, 4, a.signature.pubkey.x),
            bigint_to_array(64, 4, a.signature.pubkey.y)
        ]),
        leaf_addresses: account_data.map(a => a.wallet_data.address),
        leaf_balances: account_data.map(a => a.wallet_data.balance),
        merkle_root,
        path_elements: merkle_proofs.path_elements,
        path_indices: merkle_proofs.path_indices,
    };

    return layer_two_input;
}

var argv = require('minimist')(process.argv.slice(2), {
    alias: {
        poa_input_data_path: ['poa-input-data', 'i'],
        merkle_root_path: ['merkle-root', 't'],
        merkle_proofs_path: ['merkle-proofs', 'p'],
        x_coords_hash_path: ['write-x-coords-hash-to', 'h'],
        layer_one_sanitized_proof_path: ['layer-one-sanitized-proof', 'd'],
        layer_two_input_path: ['write-layer-two-data-to', 'o'],
    },
    default: {
        poa_input_data_path: path.join(__dirname, "../tests/input_data_for_2_wallets.json"),
        merkle_root_path: path.join(__dirname, "../tests/merkle_root.json"),
        merkle_proofs_path: path.join(__dirname, "../tests/merkle_proofs.json"),
        x_coords_hash_path: path.join(__dirname, "../tests/pubkey_x_coords_hash.txt"),
        layer_one_sanitized_proof_path: path.join(__dirname, "../build/tests/layer_one/sanitized_proof.json"),
        layer_two_input_path: path.join(__dirname, "../tests/layer_two/input.json"),
    }
});

let input_data_path = argv.poa_input_data_path;
let merkle_root_path = argv.merkle_root_path;
let merkle_proofs_path = argv.merkle_proofs_path;
let x_coords_hash_path = argv.x_coords_hash_path;
let layer_one_sanitized_proof_path = argv.layer_one_sanitized_proof_path;
let layer_two_input_path = argv.layer_two_input_path;

let input_data_raw = fs.readFileSync(input_data_path);
let input_data: ProofOfAssetsInputFileShape = JSON.parse(input_data_raw, jsonReviver);

write_pubkey_x_coords_hash(input_data.account_data.map(w => w.signature.pubkey), x_coords_hash_path)
    .then(x_coords_hash => {
        let merkle_root_raw = fs.readFileSync(merkle_root_path);
        let merkle_root: bigint = JSON.parse(merkle_root_raw, jsonReviver);

        let merkle_proofs_raw = fs.readFileSync(merkle_proofs_path);
        let merkle_proofs: Proofs = JSON.parse(merkle_proofs_raw, jsonReviver);

        var proof_data_raw = fs.readFileSync(layer_one_sanitized_proof_path);
        var proof_data: Groth16ProofAsInput = JSON.parse(proof_data_raw, jsonReviver);

        var layer_two_input: LayerTwoInputFileShape = construct_input(proof_data, x_coords_hash, input_data.account_data, merkle_root, merkle_proofs);

        const json_out = JSON.stringify(
            layer_two_input,
            (key, value) => typeof value === "bigint" ? value.toString() : value,
            2
        );

        fs.writeFileSync(layer_two_input_path, json_out);
    });
