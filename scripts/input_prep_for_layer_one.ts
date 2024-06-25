/**
Format data for use in layer 1 circuit.

This script takes the output of ecdsa_sigs_parser.ts `ProofOfAssetsInputFileShape`
and converts it to the format required by the layer 1 circuit:
`LayerOneInputFileShape`.

Note that the output of ecdsa_sigs_parser.ts contains all the signatures, but
we only want to take a portion of them for each batch. We can choose which
portion via the index options in the CLI.

Some of this code was taken from
https://github.com/puma314/batch-ecdsa/blob/b512c651f497985a74858154e4a69bcdaf02443e/test/utils.ts
**/

import { Point, CURVE } from '@noble/secp256k1';

import { jsonReviver } from "./lib/json_serde";
import { EcdsaStarSignature, ProofOfAssetsInputFileShape } from "./lib/interfaces";
import { bigint_to_array, Uint8Array_to_bigint } from "./lib/utils";

const fs = require('fs');
const circomlibjs = require("circomlibjs");
const path = require('path');

interface LayerOneInputFileShape {
    r: bigint[][],
    s: bigint[][],
    rprime: bigint[][],
    pubkey: bigint[][][],
    msghash: bigint[][],
}

function constructInput(sigs: EcdsaStarSignature[]): LayerOneInputFileShape {
    var output: LayerOneInputFileShape = {
        r: [],
        s: [],
        rprime: [],
        pubkey: [],
        msghash: [],
    };

    sigs.map(sig => {
        output.r.push(bigint_to_array(64, 4, sig.r));
        output.s.push(bigint_to_array(64, 4, sig.s));
        output.rprime.push(bigint_to_array(64, 4, sig.r_prime));
        output.pubkey.push([bigint_to_array(64, 4, sig.pubkey.x), bigint_to_array(64, 4, sig.pubkey.y)]);
        output.msghash.push(bigint_to_array(64, 4, Uint8Array_to_bigint(sig.msghash)));
    });

    return output;
}

var argv = require('minimist')(process.argv.slice(2), {
    alias: {
        poaInputDataPath: ['poa-input-data', 'i'],
        layerOneInputPath: ['write-layer-one-data-to', 'o'],
        accountStartIndex: ['account-start-index', 's'],
        accountEndIndex: ['account-end-index', 'e'],
    },
    default: {
        poaInputDataPath: path.join(__dirname, "../tests/input_data_for_2_accounts.json"),
        layerOneInputPath: path.join(__dirname, "../tests/layer_one/input.json"),
        accountStartIndex: 0,
        accountEndIndex: -1,
    }
});

var inputDataPath = argv.poaInputDataPath;
var layerOneInputPath = argv.layerOneInputPath;
var startIndex = argv.accountStartIndex;
var endIndex = argv.accountEndIndex;

fs.readFile(inputDataPath, function read(err: any, json_in: any) {
    if (err) {
        throw err;
    }

    var inputData: ProofOfAssetsInputFileShape = JSON.parse(json_in, jsonReviver);

    if (endIndex === -1) {
        endIndex = inputData.accountAttestations.length;
    }

    if (startIndex >= endIndex) {
        throw new Error(`startIndex ${startIndex} must be less than endIndex ${endIndex}`);
    }

    var layerOneInput: LayerOneInputFileShape = constructInput(
        inputData.accountAttestations.map(w => w.signature).slice(startIndex, endIndex)
    );

    const jsonOut = JSON.stringify(
        layerOneInput,
        (key, value) => typeof value === "bigint" ? value.toString() : value,
        2
    );

    fs.writeFileSync(layerOneInputPath, jsonOut);
});
