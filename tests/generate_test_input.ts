// This script is used for creating ECDSA signatures for testing.
//
// Use like this: `npx ts-node ./tests/generate_ecdsa_signatures.ts -n 5 -m "message to sign" -p`
// -n : number of signatures to generate (max 128)
// -m : message to sign
// -p : print signatures
//
// A json file will be written with the signature data.

import { sign, Point, CURVE } from '@noble/secp256k1';
import { randomBytes } from '@noble/hashes/utils';
import { Wallet } from "ethers";

import { Signature, ProofOfAssetsInputFileShape, AccountData, AccountAttestation } from "../scripts/lib/interfaces";
import { jsonReplacer } from "../scripts/lib/json_serde";
import { Uint8Array_to_bigint, bigint_to_Uint8Array } from "../scripts/lib/utils";
import { generate_pvt_pub_key_pairs } from "./keys";

const { sha256 } = require('@noble/hashes/sha256');
const fs = require('fs');
const path = require('path');
const parseArgs = require('minimist');

export function generate_deterministic_balance(key_pair: KeyPair): bigint {
    return key_pair.pvt % 1000n;
}

// Calculates a modulo b
function mod(a: bigint, b: bigint = CURVE.P): bigint {
    const result = a % b;
    return result >= 0n ? result : b + result;
}

// Inverses number over modulo
function invert(number: bigint, modulo: bigint = CURVE.P): bigint {
    if (number === 0n || modulo <= 0n) {
        throw new Error(`invert: expected positive integers, got n=${number} mod=${modulo}`);
    }

    // Eucledian GCD https://brilliant.org/wiki/extended-euclidean-algorithm/
    let a = mod(number, modulo);
    let b = modulo;
    let x = 0n, y = 1n, u = 1n, v = 0n;

    while (a !== 0n) {
        const q = b / a;
        const r = b % a;
        const m = x - u * q;
        const n = y - v * q;
        b = a, a = r, x = u, y = v, u = m, v = n;
    }
    const gcd = b;
    if (gcd !== 1n) throw new Error('invert: does not exist');

    return mod(x, modulo);
}

// computing v = r_i' in R_i = (r_i, r_i')
function construct_r_prime(r: bigint, s: bigint, pvtkey: bigint, msg_hash: Uint8Array): bigint {
    const { n } = CURVE;

    var msg_hash_bigint: bigint = Uint8Array_to_bigint(msg_hash);

    var p_1 = Point.BASE.multiply(mod(msg_hash_bigint * invert(s, n), n));
    var p_2 = Point.fromPrivateKey(pvtkey).multiply(mod(r * invert(s, n), n));
    var p_res = p_1.add(p_2);

    return p_res.y;
}

// Signature values are returned as bigints.
async function ecdsa_star(msghash: Uint8Array, key_pair: KeyPair): Promise<Signature> {
    var pvtkey = key_pair.pvt;
    var pubkey = key_pair.pub;

    var sig: Uint8Array = await sign(msghash, bigint_to_Uint8Array(pvtkey), {
        canonical: true,
        der: false,
    });

    var r: bigint = Uint8Array_to_bigint(sig.slice(0, 32));
    var s: bigint = Uint8Array_to_bigint(sig.slice(32, 64));
    var r_prime: bigint = construct_r_prime(r, s, pvtkey, msg_hash);

    return { r, s, r_prime, pubkey };
}

// Constructs a json object with ECDSA* signatures, eth addresses, and balances
async function generate_input_data(msghash: Uint8Array, key_pairs: KeyPair[]): Promise<ProofOfAssetsInputFileShape> {
    let account_data: AccountAttestation[] = [];

    for (var i = 0; i < key_pairs.length; i++) {
        let pvt_hex = key_pairs[i].pvt.toString(16);
        let address_hex = new Wallet(pvt_hex).address;
        let address_dec: bigint = BigInt(address_hex);
        let signature = await ecdsa_star(msg_hash, key_pairs[i]);

        account_data.push({
            signature,
            wallet_data: {
                address: address_dec,
                balance: generate_deterministic_balance(key_pairs[i]),
            }
        });
    }

    // It's very important to sort by address, otherwise the layer 2 circuit will fail.
    account_data.sort((a, b) => {
        if (a.wallet_data.address < b.wallet_data.address) return -1;
        else if (a.wallet_data.address > b.wallet_data.address) return 1;
        else return 0;
    });

    return {
        account_data,
        msg_hash,
    };
}

var argv = parseArgs(process.argv.slice(2), {
    alias: { num_sigs: ['num-sigs', 'n'], msg: ['message', 'm'], print_data: ['print', 'p'] },
    default: { num_sigs: 2, msg: "my message to sign", print_data: false }
});
var num_sigs = argv.num_sigs;
var msg = argv.msg;

var msg_hash: Uint8Array = sha256(msg);
var pairs = generate_pvt_pub_key_pairs(argv.n);

generate_input_data(msg_hash, pairs).then(data => {
    var filename = "input_data_for_" + num_sigs + "_wallets.json";

    const json = JSON.stringify(data, jsonReplacer, 2);

    if (argv.p === true) {
        console.log("Writing the following data to", filename, data);
    }

    fs.writeFileSync(path.join(__dirname, filename), json);
});

