/**
Format data for use in layer 2 circuit.

This script takes
1. the output of ecdsa_sigs_parser.ts: `ProofOfAssetsInputFileShape`
2. merkle root (`bigint`) & proofs (`MerkleProofs`) from merkle_tree.rs
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
    MerkleProofs,
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
    var roundLengthMax = 16;
    var numRounds = Math.floor(inputs.length / roundLengthMax);
    var outLength = 1;
    var roundLength = roundLengthMax;
    var lastRoundLength = roundLengthMax;
    var hashOut: any = 0n;

    if (inputs.length % roundLengthMax > 0) {
        numRounds++;
        lastRoundLength = inputs.length % roundLengthMax;
    }

    const poseidon = await circomlibjs.buildPoseidonOpt();

    for (var i = 0; i < numRounds; i++) {
        var intermediateInputs: bigint[] = [];
        var initialState: any = hashOut;

        if (i === numRounds - 1) {
            outLength = 2;
            roundLength = lastRoundLength;
        }

        for (var j = 0; j < roundLength; j++) {
            intermediateInputs[j] = inputs[i * roundLength + j];
        }

        hashOut = await poseidon(intermediateInputs, initialState, outLength);
    }

    const field = poseidon.F;
    return await field.toObject(hashOut[1]);
}

async function hashXCoords(xCoords: bigint[]): Promise<string> {
    let hash: bigint = await poseidonSponge(xCoords);
    return hash.toString();
}

async function writePubkeyXCoordsHash(pubkeys: Point[], outputPath: String): Promise<string> {
    let xCoords = pubkeys.map(pubkey => bigint_to_array(64, 4, pubkey.x)).flat();
    let hash = await hashXCoords(xCoords);

    console.log(`Hash of public keys x-coords: ${hash}`);

    fs.writeFileSync(outputPath, hash);

    return hash;
}

// =========================================================
// Input signal builder for the circuit.

function constructInput(proofData: Groth16ProofAsInput, xCoordsHash: string, accountAttestations: AccountAttestation[], merkleRoot: bigint, merkleProofs: MerkleProofs): LayerTwoInputFileShape {
    var { pubInput, ...otherData } = proofData;

    var layerTwoInput: LayerTwoInputFileShape = {
        ...otherData,
        pubkey_x_coord_hash: xCoordsHash,
        pubkey: accountAttestations.map(a => [
            bigint_to_array(64, 4, a.signature.pubkey.x),
            bigint_to_array(64, 4, a.signature.pubkey.y)
        ]),
        leaf_addresses: accountAttestations.map(a => a.accountData.address),
        leaf_balances: accountAttestations.map(a => a.accountData.balance),
        merkle_root: merkleRoot,
        path_elements: merkleProofs.path_elements,
        path_indices: merkleProofs.path_indices,
    };

    return layerTwoInput;
}

// =========================================================
// Checks.

// accountAttestations & merkleLeaves come from 2 different files so it's not guaranteed that
// each element of the one corresponds to the other. This is checked here. We also check
// that the addresses are in ascending order, which is required by the circuit so that
// the prover cannot do a double-spend attack.
function checkAddressOrdering(accountAttestations: AccountAttestation[], merkleLeaves: Leaf[]) {
    console.log("Checking that the order of addresses in input data & Merkle proofs is the same..")

    if (accountAttestations.length != merkleLeaves.length) {
        throw new Error(`Length of input data array ${accountAttestations.length} should equal length of merkle proofs array ${merkleLeaves.length}`);
    }

    for (let i = 0; i < accountAttestations.length; i++) {
        let addrInput: bigint = accountAttestations[i].accountData.address;
        let addrMerkle: bigint = merkleLeaves[i].address;

        if (addrInput != addrMerkle) {
            throw new Error(`[i = ${i}] Address in input data array ${addrInput} should equal address in merkle proofs array ${addrMerkle}`);
        }

        // Check ascending order.
        if (i > 0) {
            let addrMerklePrev = merkleLeaves[i - 1].address;

            if (addrMerkle < addrMerklePrev) {
                throw new Error(`Addresses must be in ascending order, but address at i=${i} (${addrMerkle}) is less than the previous address (${addrMerklePrev})`);
            } else if (addrMerkle === addrMerklePrev) {
                throw new Error(`Cannot have duplicate addresses, but address at i=${i} (${addrMerkle}) is the same as the previous address (${addrMerklePrev})`);
            }
        }
    }
}

// =========================================================
// Main execution flow.

var argv = require('minimist')(process.argv.slice(2), {
    alias: {
        poaInputDataPath: ['poa-input-data', 'i'],
        merkleRootPath: ['merkle-root', 't'],
        merkleProofsPath: ['merkle-proofs', 'p'],
        xCoordsHashPath: ['write-x-coords-hash-to', 'h'],
        layerOneSanitizedProofPath: ['layer-one-sanitized-proof', 'd'],
        layerTwoInputPath: ['write-layer-two-data-to', 'o'],
        accountStartIndex: ['account-start-index', 's'],
        accountEndIndex: ['account-end-index', 'e'],
    },
    default: {
        poaInputDataPath: path.join(__dirname, "../tests/input_data_for_32_accounts.json"),
        merkleRootPath: path.join(__dirname, "../tests/merkle_root.json"),
        merkleProofsPath: path.join(__dirname, "../tests/merkle_proofs.json"),
        xCoordsHashPath: path.join(__dirname, "../tests/pubkey_x_coords_hash.txt"),
        layerOneSanitizedProofPath: path.join(__dirname, "../build/tests/layer_one/sanitized_proof.json"),
        layerTwoInputPath: path.join(__dirname, "../tests/layer_two/input.json"),
        accountStartIndex: 0,
        accountEndIndex: -1,
    }
});

let inputDataPath = argv.poaInputDataPath;
let merkleRootPath = argv.merkleRootPath;
let merkleProofsPath = argv.merkleProofsPath;
let xCoordsHashPath = argv.xCoordsHashPath;
let layerOneSanitizedProofPath = argv.layerOneSanitizedProofPath;
let layerTwoInputPath = argv.layerTwoInputPath;
let startIndex = argv.accountStartIndex;
let endIndex = argv.accountEndIndex;

let inputDataRaw = fs.readFileSync(inputDataPath);
let inputData: ProofOfAssetsInputFileShape = JSON.parse(inputDataRaw, jsonReviver);

console.log(`Preparing input for layer 2 using the following data:
- System input: ${inputDataPath}
- Start index for batch: ${startIndex}
- End index for batch: ${endIndex}
- Merkle proofs path: ${merkleProofsPath}
- Merkle root path: ${merkleRootPath}
Path to write processed data to: ${layerTwoInputPath}
Path to write public keys hash to: ${xCoordsHashPath}
`);

if (endIndex === -1) {
    console.log("Batch contains all input data i.e. there is only 1 batch");
    endIndex = inputData.accountAttestations.length;
}

if (startIndex >= endIndex) {
    throw new Error(`startIndex ${startIndex} must be less than endIndex ${endIndex}`);
}

let accountAttestations = inputData.accountAttestations.slice(startIndex, endIndex);

writePubkeyXCoordsHash(accountAttestations.map(w => w.signature.pubkey), xCoordsHashPath)
    .then(xCoordsHash => {
        let merkleRootRaw = fs.readFileSync(merkleRootPath);
        let merkleRoot: bigint = JSON.parse(merkleRootRaw, jsonReviver);

        let merkleProofsRaw = fs.readFileSync(merkleProofsPath);
        let merkleProofs: MerkleProofs = JSON.parse(merkleProofsRaw, jsonReviver);

        let merkleProofsSlice: MerkleProofs = {
            leaves: merkleProofs.leaves.slice(startIndex, endIndex),
            path_elements: merkleProofs.path_elements.slice(startIndex, endIndex),
            path_indices: merkleProofs.path_indices.slice(startIndex, endIndex),
        }

        var proofDataRaw = fs.readFileSync(layerOneSanitizedProofPath);
        var proofData: Groth16ProofAsInput = JSON.parse(proofDataRaw, jsonReviver);

        checkAddressOrdering(accountAttestations, merkleProofsSlice.leaves);

        var layerTwoInput: LayerTwoInputFileShape = constructInput(proofData, xCoordsHash, accountAttestations, merkleRoot, merkleProofsSlice);

        const jsonOut = JSON.stringify(
            layerTwoInput,
            (_, value) => typeof value === "bigint" ? value.toString() : value,
            2
        );

        fs.writeFileSync(layerTwoInputPath, jsonOut);
    });
