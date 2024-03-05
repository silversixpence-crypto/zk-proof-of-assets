// Some of this code was taken from
// https://github.com/puma314/batch-ecdsa/blob/b512c651f497985a74858154e4a69bcdaf02443e/test/utils.ts

import { Point, CURVE } from '@noble/secp256k1';

import { jsonReviver } from "./lib/json_serde";
import { Signature, ProofOfAssetsInputFileShape } from "./lib/interfaces";
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

function construct_input(sigs: Signature[], msg_hash: Uint8Array): LayerOneInputFileShape {
    var msg_hash_bigint: bigint = Uint8Array_to_bigint(msg_hash);

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
        output.msghash.push(bigint_to_array(64, 4, msg_hash_bigint));
    });

    return output;
}

var argv = require('minimist')(process.argv.slice(2), {
    alias: {
        poa_input_data_path: ['poa-input-data', 'i'],
        layer_one_input_path: ['write-layer-one-data-to', 'o'],
    },
    default: {
        poa_input_data_path: path.join(__dirname, "../tests/input_data_for_2_accounts.json"),
        layer_one_input_path: path.join(__dirname, "../tests/layer_one/input.json"),
    }
});

var input_data_path = argv.poa_input_data_path;
var layer_one_input_path = argv.layer_one_input_path;

fs.readFile(input_data_path, function read(err: any, json_in: any) {
    if (err) {
        throw err;
    }

    var input_data: ProofOfAssetsInputFileShape = JSON.parse(json_in, jsonReviver);
    var layer_one_input: LayerOneInputFileShape = construct_input(
        input_data.account_data.map(w => w.signature),
        input_data.msg_hash
    );

    const json_out = JSON.stringify(
        layer_one_input,
        (key, value) => typeof value === "bigint" ? value.toString() : value,
        2
    );

    fs.writeFileSync(layer_one_input_path, json_out);
});
