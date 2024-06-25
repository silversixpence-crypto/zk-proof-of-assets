# Testing

This directory contains all the testing scripts & results.

TODO say more

# Summary of scripts in this directory

## [Generate test anonymity set](./generate_anon_set.ts)

Generate an anonymity set for testing.

Example CLI usage:
```bash
npx ts-node ./tests/generate_anon_set.ts --num-addresses 1000
```

The addresses & balances are deterministically chosen. Addresses are first taken
from keys.ts, then, if more addresses are needed, random_ethereum_addresses.json
is used. The max supported anonymity set size is the sum of addresses in these
2 files:
- 10k for random_ethereum_addresses.json
- 600 for keys.ts

Output file is anonymity_set.csv with headings 'address,eth_balance'

## [Generate test signatures](./generate_test_input.ts)

This script is used for creating ECDSA signatures & Ethereum addresses for testing.

Use like this: `npx ts-node ./tests/generate_ecdsa_signatures.ts -n 5 -m "message to sign" -p`
-n : number of signatures to generate (max 128)
-m : message to sign
-p : print signatures

The keys for the signatures are deterministically taken from keys.ts

A json file will be written that has the shape `SignatureData[]`.

## [Private keys](./keys.ts)

List of private keys for testing. The private keys are all private keys for secp256k1.

