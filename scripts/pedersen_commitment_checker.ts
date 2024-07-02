/*
Verify that the Pedersen commitment calculated from the secret values
matches the one that was outputted by the layer 3 circuit.

```bash
npx ts-node ./scripts/pedersen_commitment_checker.ts \
              --layer-three-public-inputs <json_with_public_inputs_for_layer_3_circuit> \
              --blinding-factor <blinding_factor>
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
        blindingFactor: ['blinding-factor', 'b'],
    },
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
