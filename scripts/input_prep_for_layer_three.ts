import { Point, CURVE } from '@noble/secp256k1';
import { jsonReviver } from "./lib/json_serde";
import { Signature, ProofOfAssetsInputFileShape, Groth16ProofAsInput, AccountAttestation, Proofs } from "./lib/interfaces";
import { bigint_to_array, bigint_to_Uint8Array } from "./lib/utils";

const fs = require('fs');
const circomlibjs = require("circomlibjs");
const path = require('path');

interface LayerThreeInputFileShape extends Omit<Groth16ProofAsInput, 'pubInput'> {
    balances: bigint[],
    merkle_root: bigint,
}

function construct_input(proof_data: Groth16ProofAsInput, balances: bigint[], merkle_root: bigint): LayerThreeInputFileShape {
    var { pubInput, ...other_data } = proof_data;

    var layer_three_input: LayerThreeInputFileShape = {
        ...other_data,
        balances,
        merkle_root,
    };

    return layer_three_input;
}

var argv = require('minimist')(process.argv.slice(2), {
    alias: {
        poa_input_data_path: ['poa-input-data', 'i'],
        merkle_root_path: ['merkle-root', 't'],
        layer_two_sanitized_proof_path: ['layer-two-sanitized-proof', 'd'],
        layer_three_input_path: ['write-layer-three-data-to', 'o'],
    },
    default: {
        poa_input_data_path: path.join(__dirname, "../tests/input_data_for_2_wallets.json"),
        merkle_root_path: path.join(__dirname, "../tests/merkle_root.json"),
        layer_two_sanitized_proof_path: path.join(__dirname, "../build/tests/layer_two/sanitized_proof.json"),
        layer_three_input_path: path.join(__dirname, "../tests/layer_three/input.json"),
    }
});

let input_data_path = argv.poa_input_data_path;
let merkle_root_path = argv.merkle_root_path;
let layer_two_sanitized_proof_path = argv.layer_two_sanitized_proof_path;
let layer_three_input_path = argv.layer_three_input_path;

let input_data_raw = fs.readFileSync(input_data_path);
let input_data: ProofOfAssetsInputFileShape = JSON.parse(input_data_raw, jsonReviver);

// TODO need to split up the accounts into pods/sections
let balances: bigint[] = [input_data.account_data.reduce(
    (accumulator, curr_value) => accumulator + curr_value.wallet_data.balance,
    0n
)];

let merkle_root_raw = fs.readFileSync(merkle_root_path);
let merkle_root: bigint = JSON.parse(merkle_root_raw, jsonReviver);

var proof_data_raw = fs.readFileSync(layer_two_sanitized_proof_path);
var proof_data: Groth16ProofAsInput = JSON.parse(proof_data_raw, jsonReviver);

var layer_three_input: LayerThreeInputFileShape = construct_input(proof_data, balances, merkle_root);

const json_out = JSON.stringify(
    layer_three_input,
    (key, value) => typeof value === "bigint" ? value.toString() : value,
    2
);

fs.writeFileSync(layer_three_input_path, json_out);
