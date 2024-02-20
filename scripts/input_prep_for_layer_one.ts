// Some of this code was taken from
// https://github.com/puma314/batch-ecdsa/blob/b512c651f497985a74858154e4a69bcdaf02443e/test/utils.ts

import { Point, CURVE } from '@noble/secp256k1';
import { jsonReviver } from "./json_serde";

const fs = require('fs');
const circomlibjs = require("circomlibjs");
import path = require('path');

export interface SignaturesFileStruct {
    signatures: Signature[],
    msg_hash: Uint8Array,
}

interface LayerOneInputFileStruct {
    r: bigint[][],
    s: bigint[][],
    rprime: bigint[][],
    pubkey: bigint[][][],
    msghash: bigint[][],
}

export interface Signature {
    r: bigint,
    s: bigint,
    r_prime: bigint,
    pubkey: Point,
}

function bigint_to_array(n: number, k: number, x: bigint) {
    let mod: bigint = 1n;
    for (var idx = 0; idx < n; idx++) {
        mod = mod * 2n;
    }

    let ret: bigint[] = [];
    var x_temp: bigint = x;
    for (var idx = 0; idx < k; idx++) {
        ret.push(x_temp % mod);
        x_temp = x_temp / mod;
    }

    return ret;
}

function Uint8Array_to_bigint(x: Uint8Array) {
    var ret: bigint = 0n;
    for (var idx = 0; idx < x.length; idx++) {
        ret = ret * 256n;
        ret = ret + BigInt(x[idx]);
    }
    return ret;
}

function construct_input(sigs: Signature[], msg_hash: Uint8Array): LayerOneInputFileStruct {
    var msg_hash_bigint: bigint = Uint8Array_to_bigint(msg_hash);

    var output: LayerOneInputFileStruct = {
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

async function hash_x_coords(x_coords: bigint[]) {
    const poseidon = await circomlibjs.buildPoseidon();
    const F = poseidon.F; // poseidon finite field

    let poseidonRes = await poseidon(x_coords);
    let hash = await F.toObject(poseidonRes);

    return hash.toString();
}

function write_pubkey_x_coords_hash(sigs: Signature[], output_path: String) {
    var filename = "pubkey_x_coords.json";
    var x_coords = sigs.map(sig => bigint_to_array(64, 4, sig.pubkey.x)).flat();
    hash_x_coords(x_coords).then(hash => fs.writeFileSync(output_path, hash));
}

var argv = require('minimist')(process.argv.slice(2), {
    default: {
        "i": path.join(__dirname, "../tests/signatures_2.json"),
        "o": path.join(__dirname, "../tests/layer_one/input.json"),
        "h": path.join(__dirname, "../tests/pubkey_x_coords_hash.txt"),
    }
});

var input_path = argv.i;
var output_path = argv.o;
var x_coord_hash_output_path = argv.h;

fs.readFile(input_path, function read(err: any, json_in: any) {
    if (err) {
        throw err;
    }

    var input: SignaturesFileStruct = JSON.parse(json_in, jsonReviver);

    write_pubkey_x_coords_hash(input.signatures, x_coord_hash_output_path);

    var output: LayerOneInputFileStruct = construct_input(input.signatures, input.msg_hash);

    // Serialization
    const json_out = JSON.stringify(
        output,
        (key, value) => typeof value === "bigint" ? value.toString() : value,
        2
    );

    fs.writeFileSync(output_path, json_out);
});
