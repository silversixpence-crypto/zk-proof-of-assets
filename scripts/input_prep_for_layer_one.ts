// Some of this code was taken from
// https://github.com/puma314/batch-ecdsa/blob/b512c651f497985a74858154e4a69bcdaf02443e/test/utils.ts

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

function construct_input(sigs: EcdsaStarSignature[]): LayerOneInputFileShape {
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
        poa_input_data_path: ['poa-input-data', 'i'],
        layer_one_input_path: ['write-layer-one-data-to', 'o'],
        account_start_index: ['account-start-index', 's'],
        account_end_index: ['account-end-index', 'e'],
    },
    default: {
        poa_input_data_path: path.join(__dirname, "../tests/input_data_for_2_accounts.json"),
        layer_one_input_path: path.join(__dirname, "../tests/layer_one/input.json"),
        account_start_index: 0,
        account_end_index: -1,
    }
});

var input_data_path = argv.poa_input_data_path;
var layer_one_input_path = argv.layer_one_input_path;
var start_index = argv.account_start_index;
var end_index = argv.account_end_index;

fs.readFile(input_data_path, function read(err: any, json_in: any) {
    if (err) {
        throw err;
    }

    var input_data: ProofOfAssetsInputFileShape = JSON.parse(json_in, jsonReviver);

    if (end_index === -1) {
        end_index = input_data.accountAttestations.length;
    }

    if (start_index >= end_index) {
        throw new Error(`start_index ${start_index} must be less than end_index ${end_index}`);
    }

    var layer_one_input: LayerOneInputFileShape = construct_input(
        input_data.accountAttestations.map(w => w.signature).slice(start_index, end_index)
    );

    const json_out = JSON.stringify(
        layer_one_input,
        (key, value) => typeof value === "bigint" ? value.toString() : value,
        2
    );

    fs.writeFileSync(layer_one_input_path, json_out);
});
