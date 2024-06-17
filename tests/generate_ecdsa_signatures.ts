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
import { generatePvtPubKeyPairs, generateDeterministicBalance, KeyPair } from "./keys";

const { sha256 } = require('@noble/hashes/sha256');
const fs = require('fs');
const path = require('path');
const parseArgs = require('minimist');

async function ecdsaSign(msghash: Uint8Array, keyPair: KeyPair): Promise<EcdsaSignature> {
    var pvtkey = keyPair.pvt;
    var pubkey = keyPair.pub;

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
async function generateSignatureData(msghash: Uint8Array, keyPairs: KeyPair[]): Promise<SignatureData[]> {
    let signatureData: SignatureData[] = [];

    for (var i = 0; i < keyPairs.length; i++) {
        let pvtHex = keyPairs[i].pvt.toString(16);
        let addressHex: string = new Wallet(pvtHex).address;
        let addressDec: bigint = BigInt(addressHex);
        let signature = await ecdsaSign(msghash, keyPairs[i]);

        signatureData.push({
            signature,
            address: addressHex,
            balance: generateDeterministicBalance(keyPairs[i]).toString() + "n",
        });
    }

    // It's very important to sort by address, otherwise the layer 2 circuit will fail.
    signatureData.sort((a, b) => {
        let a_addressDec: bigint = BigInt(a.address);
        let b_addressDec: bigint = BigInt(b.address);
        if (a_addressDec < b_addressDec) return -1;
        else if (a_addressDec > b_addressDec) return 1;
        else return 0;
    });

    return signatureData;
}

var argv = parseArgs(process.argv.slice(2), {
    alias: { numSigs: ['num-sigs', 'n'], msg: ['message', 'm'], printData: ['print', 'p'] },
    default: { numSigs: 2, msg: "my message to sign", printData: false }
});
var numSigs = argv.numSigs;
var msg = argv.msg;

var msgHash: Uint8Array = sha256(msg);
var pairs = generatePvtPubKeyPairs(argv.n);

var filename = "signatures_" + numSigs + ".json";
var filePath = path.join(__dirname, filename);

generateSignatureData(msgHash, pairs).then(data => {
    if (argv.p === true) {
        console.log("Writing the following data to", filename, data);
    }

    const json = JSON.stringify(data);
    fs.writeFileSync(filePath, json);
});

console.log(`Test signature set of size ${numSigs} has been generated and written to ${filePath}`);
