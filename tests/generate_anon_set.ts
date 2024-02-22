import { Wallet } from "ethers";
import { randomBytes } from '@noble/hashes/utils';

import { generate_pvt_pub_key_pairs } from "./generate_test_input";
import { Uint8Array_to_bigint } from "../scripts/lib/utils";
import { jsonReplacer } from "../scripts/lib/json_serde";

const parseArgs = require('minimist');
const fs = require('fs');
const path = require('path');

var argv = parseArgs(process.argv.slice(2), {
    alias: { num_addresses: ['num-addresses', 'n'] },
    default: { num_addresses: 100 }
});

let num_addreses = argv.num_addresses;
let known_key_pairs = generate_pvt_pub_key_pairs();
let num_known_addresses = num_addreses > known_key_pairs.length ? known_key_pairs.length : num_addreses;

let addresses: bigint[] = [];

for (let i = 0; i < num_known_addresses; i++) {
    let pvt_hex = known_key_pairs[i].pvt.toString(16);
    let address_hex = new Wallet(pvt_hex).address;
    let address_dec: bigint = BigInt(address_hex);
    addresses.push(address_dec);
}

if (num_addreses > num_known_addresses) {
    let num_random_addresses = num_addreses - num_known_addresses;

    for (let i = 0; i < num_random_addresses; i++) {
        let address = Uint8Array_to_bigint(randomBytes(20));
        addresses.push(address);
    }
}

addresses.sort();

let filename = "anonymity_set.json";
const json = JSON.stringify(addresses, jsonReplacer, 2);
fs.writeFileSync(path.join(__dirname, filename), json);
