/*
Verify that the Pedersen commitment calculated from the secret values
matches the one that was outputted by the layer 3 circuit.

```bash
npx ts-node ./scripts/pedersen_commitment_checker.ts \
              --poa-input-data <json_with_full_system_input> \
              --layer-three-public-inputs <json_with_public_inputs_for_layer_3_circuit> \
              --blindingFactor <blinding_factor>
```

Example:
```bash
npx ts-node ./scripts/pedersen_commitment_checker.ts \
              --poa-input-data tests/4_sigs_2_batches_12_height/input_data_for_4_accounts.json
              --layer-three-public-inputs tests/4_sigs_2_batches_12_height/layer_three/public.json \
              --blindingFactor 57896044618658097711785492504343953926634992332820282019728792003956564819948 \
```
*/

import { pedersenCommitment, dechunkToPoint, pointEqual } from "./lib/pedersen_commitment";
import { jsonReviver } from "./lib/json_serde";
import { ProofOfAssetsInputFileShape } from "./lib/interfaces";
const assert = require('assert');

const fs = require('fs');

var argv = require('minimist')(process.argv.slice(2), {
    alias: {
        poaInputDataPath: ['poa-input-data', 'i'],
        layerThreePublicInputsPath: ['layer-three-public-inputs', 'p'],
    },
    // if we don't treat this as a string then there are problems converting to bigint
    string: ['blindingFactor']
});

let inputDataPath = argv.poaInputDataPath;
let layerThreePublicInputsPath = argv.layerThreePublicInputsPath;
let blindingFactor: bigint = BigInt(argv.blindingFactor);

let inputDataRaw = fs.readFileSync(inputDataPath);
let inputData: ProofOfAssetsInputFileShape = JSON.parse(inputDataRaw, jsonReviver);

let publicInputsRaw = fs.readFileSync(layerThreePublicInputsPath);
let publicInputs: string[] = JSON.parse(publicInputsRaw, jsonReviver);

let balanceSum = inputData.accountAttestations.reduce(
    (accumulator, currentValue) => currentValue.accountData.balance + accumulator,
    0n
);

console.log(`Balance sum calculated from input data: ${balanceSum}`);
console.log(`Blinding factor given: ${blindingFactor}`);

let comCalc = pedersenCommitment(balanceSum, blindingFactor);
let comCircuit = dechunkToPoint(publicInputs.map(i => BigInt(i)));

assert.ok(
    pointEqual(comCalc, comCircuit),
);
