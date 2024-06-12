/**
Generate an anonymity set for testing.

Example CLI usage:
```bash
npx ts-node ./tests/generate_anon_set.ts --num-addresses 1000
```

The addresses & balances are deterministically chosen. Addresses are first taken
from keys.ts, then, if more addresses are needed, random_ethereum_addresses.json
is used. The max supported anonymity set size is the sum of addresses in these
2 files:
- 600 for keys.ts
- 10k for random_ethereum_addresses.json

Note that generate_test_input.ts takes keys from keys.ts, so we have to populate
the anonymity set with all of these keys if we want the protocol to work.

Output file is anonymity_set.csv with headings 'address,eth_balance'
**/

import { Wallet } from "ethers";
import { randomBytes } from '@noble/hashes/utils';

import { generate_pvt_pub_key_pairs, KeyPair, generate_deterministic_balance } from "./keys";
import { bigint_to_Uint8Array, bytesToHex } from "../scripts/lib/utils";
import { jsonReplacer } from "../scripts/lib/json_serde";
import { AccountData } from "../scripts/lib/interfaces";
import { interfaces } from "mocha";

const parseArgs = require('minimist');
const fs = require('fs');
const path = require('path');
const { stringify } = require('csv-stringify');

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

let accounts: AccountData[] = [];
let i = 0;

// =============================================================================
// Add addresses from keys.ts

while (i < known_key_pairs.length && i < num_addresses) {
    let pvt_hex = known_key_pairs[i].pvt.toString(16);
    let address_hex = new Wallet(pvt_hex).address;
    let address_dec: bigint = BigInt(address_hex);

    accounts.push({
        address: address_dec,
        balance: generate_deterministic_balance(known_key_pairs[i]),
    });

    i++;
}

// =============================================================================
// Add addresses from random_ethereum_addresses.json

if (num_addresses > i) {
    num_addresses = num_addresses - i;
    for (let j = 0; j < num_addresses; j++) {
        let address: bigint = BigInt(random_address_set[j].address);
        let balance: bigint = BigInt(random_address_set[j].balance);
        accounts.push({ address, balance });
    }
}

// =============================================================================
// It's not necessary to have the addresses sorted at this stage, but it makes things
// easier to reason about when debugging.

accounts.sort((a, b) => {
    if (a.address < b.address) return -1;
    else if (a.address > b.address) return 1;
    else return 0;
});

// =============================================================================
// Write to csv.

const writableStream = fs.createWriteStream(path.join(__dirname, "anonymity_set.csv"));
const columns = ["address", "eth_balance"];
const stringifier = stringify({ header: true, columns });

accounts.forEach(account => {
    let address_hex = "0x" + bytesToHex(bigint_to_Uint8Array(account.address));
    stringifier.write([address_hex, account.balance.toString()])
}
);

stringifier.pipe(writableStream);

