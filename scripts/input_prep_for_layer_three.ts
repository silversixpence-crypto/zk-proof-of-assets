import { Point, CURVE } from '@noble/secp256k1';
import { jsonReviver } from "./lib/json_serde";
import { ProofOfAssetsInputFileShape, Groth16ProofAsInput } from "./lib/interfaces";
import { bigint_to_array, bigint_to_Uint8Array } from "./lib/utils";
import { generator_g_formatted, generator_h_formatted, format_scalar_power } from "./lib/pedersen_commitment";

const fs = require('fs');
const circomlibjs = require("circomlibjs");
const path = require('path');

interface LayerThreeInputFileShape {
    // We need the groth16 proof data for all the layer 2 circuits.
    // It looks like Groth16ProofAsInput, but each field has 1 extra array dimension
    // to account for the fact that there may be more than 1 proof to verify.
    gamma2: number[][][][],
    delta2: number[][][][],
    negalfa1xbeta2: number[][][][],
    IC: number[][][][],
    negpa: number[][][][],
    pb: number[][][][],
    pc: number[][][],

    // Public inputs for the layer 2s.
    // Note that the merkleRoot is not an array, because the values are the same for all layer 2s.
    balances: bigint[],
    merkle_root: bigint,

    // Pedersen commitment values.
    ped_com_generator_g: bigint[][],
    ped_com_generator_h: bigint[][],
    ped_com_blinding_factor: bigint[],
}

function constructInput(proofData: Groth16ProofAsInput[], balances: bigint[], merkleRoot: bigint, blindingFactor: bigint): LayerThreeInputFileShape {
    let layerThreeInput: LayerThreeInputFileShape = {
        gamma2: [],
        delta2: [],
        negalfa1xbeta2: [],
        IC: [],
        negpa: [],
        pb: [],
        pc: [],
        balances,
        merkle_root: merkleRoot,
        ped_com_generator_g: generator_g_formatted,
        ped_com_generator_h: generator_h_formatted,
        ped_com_blinding_factor: format_scalar_power(blindingFactor),
    };

    for (let i = 0; i < proofData.length; i++) {
        layerThreeInput.gamma2.push(proofData[i].gamma2);
        layerThreeInput.delta2.push(proofData[i].delta2);
        layerThreeInput.negalfa1xbeta2.push(proofData[i].negalfa1xbeta2);
        layerThreeInput.IC.push(proofData[i].IC);
        layerThreeInput.negpa.push(proofData[i].negpa);
        layerThreeInput.pb.push(proofData[i].pb);
        layerThreeInput.pc.push(proofData[i].pc);
    }

    return layerThreeInput;
}

var argv = require('minimist')(process.argv.slice(2), {
    alias: {
        merkleRootPath: ['merkle-root', 't'],
        layerTwoSanitizedProofPath: ['layer-two-sanitized-proof', 's'],
        layerThreeInputPath: ['write-layer-three-data-to', 'o'],
        multipleProofs: ['multiple-proofs', 'm'],
        blindingFactor: ['blinding-factor', 'b'],
    },
    default: {
        merkleRootPath: path.join(__dirname, "../tests/merkle_root.json"),
        layerTwoSanitizedProofPath: path.join(__dirname, "../build/tests/layer_two/sanitized_proof.json"),
        layerThreeInputPath: path.join(__dirname, "../tests/layer_three/input.json"),
        multipleProofs: false,
        blindingFactor: "4869643893319708471955165214975585939793846505679808910535986866633137979160",
    }
});

let merkleRootPath = argv.merkleRootPath;
let layerTwoSanitizedProofPath = argv.layerTwoSanitizedProofPath;
let layerThreeInputPath = argv.layerThreeInputPath;
let multipleProofs = argv.multipleProofs;
let blindingFactor: bigint = BigInt(argv.blindingFactor);

let merkleRootRaw = fs.readFileSync(merkleRootPath);
let merkleRoot: bigint = JSON.parse(merkleRootRaw, jsonReviver);

let proofDataArray: Groth16ProofAsInput[] = [];
let balances: bigint[] = [];

// TODO is this multipleProofs mechanism the best way of doing this? It's very wonky
if (multipleProofs === true) {
    // NOTE assumes layer-two-sanitized-proof cli option points to a directory
    if (!fs.lstatSync(layerTwoSanitizedProofPath).isDirectory()) {
        throw new Error(`Expected ${layerTwoSanitizedProofPath} to be a directory`);
    }

    let ls = fs.readdirSync(layerTwoSanitizedProofPath, { withFileTypes: true });

    for (const item of ls) {
        // TODO we need to have a better way of centralising names like "batch", 'cause now what happens if we change this name in the shell script?
        if (item.isDirectory() && item.name.substring(0, 6) === "batch_") {
            console.log(`Found directory ${layerTwoSanitizedProofPath}/${item.name}. Assuming it contains sanitized_proof.json`);

            let filePath = path.join(layerTwoSanitizedProofPath, item.name, "sanitized_proof.json");
            let proofDataRaw = fs.readFileSync(filePath);
            let proofData: Groth16ProofAsInput = JSON.parse(proofDataRaw, jsonReviver);

            balances.push(proofData.pubInput[0]);
            proofDataArray.push(proofData);
        }
    }
} else {
    // NOTE assumes layer-two-sanitized-proof cli option points to a file
    if (fs.lstatSync(layerTwoSanitizedProofPath).isDirectory()) {
        throw new Error(`Expected ${layerTwoSanitizedProofPath} to be a file`);
    }

    var proofDataRaw = fs.readFileSync(layerTwoSanitizedProofPath);
    var proofData: Groth16ProofAsInput = JSON.parse(proofDataRaw, jsonReviver);

    balances.push(proofData.pubInput[0]);
    proofDataArray.push(proofData);
}

let layerThreeInput: LayerThreeInputFileShape = constructInput(proofDataArray, balances, merkleRoot, blindingFactor);

const jsonOut = JSON.stringify(
    layerThreeInput,
    (key, value) => typeof value === "bigint" ? value.toString() : value,
    2
);

fs.writeFileSync(layerThreeInputPath, jsonOut);
