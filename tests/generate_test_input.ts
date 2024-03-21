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

import { EcdsaStarSignature, ProofOfAssetsInputFileShape, AccountData, AccountAttestation } from "../scripts/lib/interfaces";
import { jsonReplacer } from "../scripts/lib/json_serde";
import { Uint8Array_to_bigint, bigint_to_Uint8Array } from "../scripts/lib/utils";
import { generate_pvt_pub_key_pairs, generate_deterministic_balance, KeyPair } from "./keys";
import { mod, invert, construct_r_prime } from "../scripts/lib/ecdsa_star";

const { sha256 } = require('@noble/hashes/sha256');
const fs = require('fs');
const path = require('path');
const parseArgs = require('minimist');

// Signature values are returned as bigints.
async function ecdsa_star(msghash: Uint8Array, key_pair: KeyPair): Promise<EcdsaStarSignature> {
    var pvtkey = key_pair.pvt;
    var pubkey = key_pair.pub;

    var sig: Uint8Array = await sign(msghash, bigint_to_Uint8Array(pvtkey), {
        canonical: true,
        der: false,
    });

    var r: bigint = Uint8Array_to_bigint(sig.slice(0, 32));
    var s: bigint = Uint8Array_to_bigint(sig.slice(32, 64));
    var r_prime: bigint = construct_r_prime(r, s, pubkey, msg_hash);

    return { r, s, r_prime, pubkey, msghash };
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
            account_data: {
                address: address_dec,
                balance: generate_deterministic_balance(key_pairs[i]),
            }
        });
    }

    // It's very important to sort by address, otherwise the layer 2 circuit will fail.
    account_data.sort((a, b) => {
        if (a.account_data.address < b.account_data.address) return -1;
        else if (a.account_data.address > b.account_data.address) return 1;
        else return 0;
    });

    return {
        account_data,
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
    var filename = "input_data_for_" + num_sigs + "_accounts.json";

    const json = JSON.stringify(data, jsonReplacer, 2);

    if (argv.p === true) {
        console.log("Writing the following data to", filename, data);
    }

    fs.writeFileSync(path.join(__dirname, filename), json);
});

