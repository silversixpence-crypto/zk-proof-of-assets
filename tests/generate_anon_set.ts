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

import { generatePvtPubKeyPairs, KeyPair, generateDeterministicBalance } from "./keys";
import { bigint_to_Uint8Array, bytesToHex } from "../scripts/lib/utils";
import { AccountData } from "../scripts/lib/interfaces";

const parseArgs = require('minimist');
const fs = require('fs');
const path = require('path');
const { stringify } = require('csv-stringify');

interface AccountDataRaw {
    address: string,
    balance: string,
}

var argv = parseArgs(process.argv.slice(2), {
    alias: { numAddresses: ['num-addresses', 'n'] },
    default: { numAddresses: 100 }
});

let numAddresses: number = argv.numAddresses;

let randomAddressSetPath = path.join(__dirname, "random_ethereum_addresses.json");
let randomAddressSetRaw = fs.readFileSync(randomAddressSetPath);
let randomAddressSet: AccountDataRaw[] = JSON.parse(randomAddressSetRaw);
let knownKeyPairs: KeyPair[] = generatePvtPubKeyPairs(-1);
let totalAddressCount = knownKeyPairs.length + randomAddressSet.length;

if (numAddresses > totalAddressCount) {
    throw new Error(`Cannot generate anonymity set size greater than ${totalAddressCount}. Size requested was ${numAddresses}`);
}

let accounts: AccountData[] = [];
let i = 0;

// =============================================================================
// Add addresses from keys.ts

while (i < knownKeyPairs.length && i < numAddresses) {
    let pvtHex = knownKeyPairs[i].pvt.toString(16);
    let addressHex = new Wallet(pvtHex).address;
    let addressDec: bigint = BigInt(addressHex);

    accounts.push({
        address: addressDec,
        balance: generateDeterministicBalance(knownKeyPairs[i]),
    });

    i++;
}

// =============================================================================
// Add addresses from random_ethereum_addresses.json

if (numAddresses > i) {
    for (let j = 0; j < numAddresses - i; j++) {
        let address: bigint = BigInt(randomAddressSet[j].address);
        let balance: bigint = BigInt(randomAddressSet[j].balance);
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

const filename = "anonymity_set_" + numAddresses + ".csv";
const filePath = path.join(__dirname, filename);
const writableStream = fs.createWriteStream(filePath);
const columns = ["address", "eth_balance"];
const stringifier = stringify({ header: true, columns });

accounts.forEach(account => {
    let addressHex = "0x" + bytesToHex(bigint_to_Uint8Array(account.address));
    stringifier.write([addressHex, account.balance.toString()])
}
);

stringifier.pipe(writableStream);

console.log(`Test anonymity set of size ${numAddresses} has been generated and written to ${filePath}`);

