# Testing

This directory contains all the testing scripts & results.

TODO say more

# Summary of scripts in this directory

## [Generate test signatures](./generate_test_input.ts)

This script is used for creating ECDSA signatures & Ethereum addresses for testing.

Use like this: `npx ts-node ./tests/generate_ecdsa_signatures.ts -n 5 -m "message to sign" -p`
-n : number of signatures to generate (max 128)
-m : message to sign
-p : print signatures

A json file will be written that has the shape `SignatureData[]`.

## [Generate test anonymity set](./generate_anon_set.ts)

Generate the anonymity set.

Can give the anonymity set size via '-n' cli option.

First the addresses from keys.ts are used, then the addresses from random_ethereum_addresses.json
The max supported anon set size is the sum of addresses in these 2 files.

Output is anonymity_set.csv with headings 'address,eth_balance'
