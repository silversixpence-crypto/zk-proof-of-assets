import { Point, CURVE } from '@noble/secp256k1';
import { jsonReviver } from "./lib/json_serde";
import { Signature, ProofOfAssetsInputFileShape, Groth16ProofAsInput, AccountAttestation, Proofs } from "./lib/interfaces";
import { bigint_to_array, bigint_to_Uint8Array } from "./lib/utils";

const fs = require('fs');
const circomlibjs = require("circomlibjs");
const path = require('path');

interface LayerThreeInputFileShape {
    // Like Groth16ProofAsInput but each field has 1 extra array dimension.
    gamma2: number[][][][],
    delta2: number[][][][],
    negalfa1xbeta2: number[][][][],
    IC: number[][][][],
    negpa: number[][][][],
    pb: number[][][][],
    pc: number[][][],

    balances: bigint[],
    merkle_root: bigint,
}

function construct_input(proof_data: Groth16ProofAsInput[], balances: bigint[], merkle_root: bigint): LayerThreeInputFileShape {
    let layer_three_input: LayerThreeInputFileShape = {
        gamma2: [],
        delta2: [],
        negalfa1xbeta2: [],
        IC: [],
        negpa: [],
        pb: [],
        pc: [],
        balances,
        merkle_root,
    };

    for (let i = 0; i < proof_data.length; i++) {
        layer_three_input.gamma2.push(proof_data[i].gamma2);
        layer_three_input.delta2.push(proof_data[i].delta2);
        layer_three_input.negalfa1xbeta2.push(proof_data[i].negalfa1xbeta2);
        layer_three_input.IC.push(proof_data[i].IC);
        layer_three_input.negpa.push(proof_data[i].negpa);
        layer_three_input.pb.push(proof_data[i].pb);
        layer_three_input.pc.push(proof_data[i].pc);
    }

    return layer_three_input;
}

var argv = require('minimist')(process.argv.slice(2), {
    alias: {
        poa_input_data_path: ['poa-input-data', 'i'],
        merkle_root_path: ['merkle-root', 't'],
        layer_two_sanitized_proof_path: ['layer-two-sanitized-proof', 's'],
        layer_three_input_path: ['write-layer-three-data-to', 'o'],
        multiple_proofs: ['multiple-proofs', 'm'],
    },
    default: {
        poa_input_data_path: path.join(__dirname, "../tests/input_data_for_2_accounts.json"),
        merkle_root_path: path.join(__dirname, "../tests/merkle_root.json"),
        layer_two_sanitized_proof_path: path.join(__dirname, "../build/tests/layer_two/sanitized_proof.json"),
        layer_three_input_path: path.join(__dirname, "../tests/layer_three/input.json"),
        multiple_proofs: false,
    }
});

let input_data_path = argv.poa_input_data_path;
let merkle_root_path = argv.merkle_root_path;
let layer_two_sanitized_proof_path = argv.layer_two_sanitized_proof_path;
let layer_three_input_path = argv.layer_three_input_path;
let multiple_proofs = argv.multiple_proofs;

let input_data_raw = fs.readFileSync(input_data_path);
let input_data: ProofOfAssetsInputFileShape = JSON.parse(input_data_raw, jsonReviver);

let merkle_root_raw = fs.readFileSync(merkle_root_path);
let merkle_root: bigint = JSON.parse(merkle_root_raw, jsonReviver);

let proof_data_array: Groth16ProofAsInput[] = [];
let balances: bigint[] = [];

if (multiple_proofs === true) {
    // NOTE assumes layer-two-sanitized-proof cli option points to a directory
    if (!fs.lstatSync(layer_two_sanitized_proof_path).isDirectory()) {
        throw new Error(`Expected ${layer_two_sanitized_proof_path} to be a directory`);
    }

    let ls = fs.readdirSync(layer_two_sanitized_proof_path, { withFileTypes: true });

    for (const item of ls) {
        // TODO we need to have a better way of centralising names like "batch", 'cause now what happens if we change this name in the shell script?
        if (item.isDirectory() && item.name.substring(0,6) === "batch_") {
            console.log(`Found directory ${layer_two_sanitized_proof_path}/${item.name}. Assuming it contains sanitized_proof.json`);

            let file_path = path.join(layer_two_sanitized_proof_path, item.name, "sanitized_proof.json");
            let proof_data_raw = fs.readFileSync(file_path);
            let proof_data: Groth16ProofAsInput = JSON.parse(proof_data_raw, jsonReviver);

            balances.push(proof_data.pubInput[0]);
            proof_data_array.push(proof_data);
        }
    }
} else {
    // NOTE assumes layer-two-sanitized-proof cli option points to a file
    if (fs.lstatSync(layer_two_sanitized_proof_path).isDirectory()) {
        throw new Error(`Expected ${layer_two_sanitized_proof_path} to be a file`);
    }

    var proof_data_raw = fs.readFileSync(layer_two_sanitized_proof_path);
    var proof_data: Groth16ProofAsInput = JSON.parse(proof_data_raw, jsonReviver);

    balances.push(proof_data.pubInput[0]);
    proof_data_array.push(proof_data);
}

let layer_three_input: LayerThreeInputFileShape = construct_input(proof_data_array, balances, merkle_root);

const json_out = JSON.stringify(
    layer_three_input,
    (key, value) => typeof value === "bigint" ? value.toString() : value,
    2
);

fs.writeFileSync(layer_three_input_path, json_out);
