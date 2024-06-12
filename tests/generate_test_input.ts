/**
   This script is used for creating ECDSA signatures & Ethereum addresses for testing.

   Use like this: `npx ts-node ./tests/generate_ecdsa_signatures.ts -n 5 -m "message to sign" -p`
   -n : number of signatures to generate (max 128)
   -m : message to sign
   -p : print signatures

   The keys for the signatures are deterministically taken from keys.ts

   A json file will be written that has the shape `SignatureData[]`.
**/

import { sign, Point, CURVE } from '@noble/secp256k1';
import { randomBytes } from '@noble/hashes/utils';
import { Wallet } from "ethers";

import { EcdsaSignature, SignatureData, } from "../scripts/lib/interfaces";
import { jsonReplacer } from "../scripts/lib/json_serde";
import { Uint8Array_to_bigint, bigint_to_Uint8Array, bytesToHex } from "../scripts/lib/utils";
import { generate_pvt_pub_key_pairs, generate_deterministic_balance, KeyPair } from "./keys";

const { sha256 } = require('@noble/hashes/sha256');
const fs = require('fs');
const path = require('path');
const parseArgs = require('minimist');

async function ecdsa_sign(msghash: Uint8Array, key_pair: KeyPair): Promise<EcdsaSignature> {
    var pvtkey = key_pair.pvt;
    var pubkey = key_pair.pub;

    var sig: Uint8Array = await sign(msghash, bigint_to_Uint8Array(pvtkey), {
        canonical: true,
        der: false,
    });

    return {
        r: '0x' + bytesToHex(sig.slice(0, 32)),
        s: '0x' + bytesToHex(sig.slice(32, 64)),
        v: 28,
        msghash: '0x' + bytesToHex(msghash)
    };
}

// Constructs a json object with ECDSA signatures, eth addresses, and balances
async function generate_signature_data(msghash: Uint8Array, key_pairs: KeyPair[]): Promise<SignatureData[]> {
    let signature_data: SignatureData[] = [];

    for (var i = 0; i < key_pairs.length; i++) {
        let pvt_hex = key_pairs[i].pvt.toString(16);
        let address_hex: string = new Wallet(pvt_hex).address;
        let address_dec: bigint = BigInt(address_hex);
        let signature = await ecdsa_sign(msghash, key_pairs[i]);

        signature_data.push({
            signature,
            address: address_hex,
            balance: generate_deterministic_balance(key_pairs[i]).toString() + "n",
        });
    }

    // It's very important to sort by address, otherwise the layer 2 circuit will fail.
    signature_data.sort((a, b) => {
        let a_address_dec: bigint = BigInt(a.address);
        let b_address_dec: bigint = BigInt(b.address);
        if (a_address_dec < b_address_dec) return -1;
        else if (a_address_dec > b_address_dec) return 1;
        else return 0;
    });

    return signature_data;
}

var argv = parseArgs(process.argv.slice(2), {
    alias: { num_sigs: ['num-sigs', 'n'], msg: ['message', 'm'], print_data: ['print', 'p'] },
    default: { num_sigs: 2, msg: "my message to sign", print_data: false }
});
var num_sigs = argv.num_sigs;
var msg = argv.msg;

var msg_hash: Uint8Array = sha256(msg);
var pairs = generate_pvt_pub_key_pairs(argv.n);

generate_signature_data(msg_hash, pairs).then(data => {
    var filename = "input_data_for_" + num_sigs + "_accounts.json";

    if (argv.p === true) {
        console.log("Writing the following data to", filename, data);
    }

    const json = JSON.stringify(data);
    fs.writeFileSync(path.join(__dirname, filename), json);
});
