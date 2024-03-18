// Generate the anonymity set.
//
// Can give the anonymity set size via '-n' cli option.
//
// First the addresses from keys.ts are used, then the addresses from random_ethereum_addresses.json
// The max supported anon set size is the sum of addresses in these 2 files.

import { Wallet } from "ethers";
import { randomBytes } from '@noble/hashes/utils';

import { generate_pvt_pub_key_pairs, KeyPair, generate_deterministic_balance } from "./keys";
import { Uint8Array_to_bigint } from "../scripts/lib/utils";
import { jsonReplacer } from "../scripts/lib/json_serde";
import { AccountData } from "../scripts/lib/interfaces";
import { interfaces } from "mocha";

const parseArgs = require('minimist');
const fs = require('fs');
const path = require('path');

interface AccountDataRaw {
    address: string,
    balance: string,
}

var argv = parseArgs(process.argv.slice(2), {
    alias: { num_addresses: ['num-addresses', 'n'] },
    default: { num_addresses: 100 }
});

let num_addresses: number = argv.num_addresses;

let random_address_set_path = path.join(__dirname, "random_ethereum_addresses.json");
let random_address_set_raw = fs.readFileSync(random_address_set_path);
let random_address_set: AccountDataRaw[] = JSON.parse(random_address_set_raw);
let known_key_pairs: KeyPair[] = generate_pvt_pub_key_pairs(-1);
let total_address_count = known_key_pairs.length + random_address_set.length;

if (num_addresses > total_address_count) {
    throw new Error(`Cannot generate anonymity set size greater than ${total_address_count}. Size requested was ${num_addresses}`);
}

let addresses: AccountData[] = [];
let i = 0;

while (i < known_key_pairs.length && i < num_addresses) {
    let pvt_hex = known_key_pairs[i].pvt.toString(16);
    let address_hex = new Wallet(pvt_hex).address;
    let address_dec: bigint = BigInt(address_hex);

    addresses.push({
        address: address_dec,
        balance: generate_deterministic_balance(known_key_pairs[i]),
    });

    i++;
}

if (num_addresses > i) {
    num_addresses = num_addresses - i;
    for (let j = 0; j < num_addresses; j++) {
        let address: bigint = BigInt(random_address_set[j].address);
        let balance: bigint = BigInt(random_address_set[j].balance);
        addresses.push({ address, balance });
    }
}

// It's not necessary to have the addresses sorted at this stage, but it makes things
// easier to reason about when debugging.
addresses.sort();

const json = JSON.stringify(addresses, jsonReplacer, 2);
fs.writeFileSync(path.join(__dirname, "anonymity_set.json"), json);

