import { generator_g_formatted, generator_h_formatted, format_scalar_power, pedersen_commitment, dechunk_to_point, point_equal } from "./lib/pedersen_commitment";
import { jsonReviver } from "./lib/json_serde";
import { ProofOfAssetsInputFileShape } from "./lib/interfaces";
const assert = require('assert');

const fs = require('fs');
const circomlibjs = require("circomlibjs");
const path = require('path');

var argv = require('minimist')(process.argv.slice(2), {
    alias: {
        poaInputDataPath: ['poa-input-data', 'i'],
        layerThreePublicInputsPath: ['layer-three-public-inputs', 'p'],
        blindingFactor: ['blinding-factor', 'b'],
    },
    default: {
        poaInputDataPath: path.join(__dirname, "../tests/input_data_for_2_accounts.json"),
        blindingFactor: "4869643893319708471955165214975585939793846505679808910535986866633137979160",
    }
});

let inputDataPath = argv.poaInputDataPath;
let layerThreePublicInputsPath = argv.layerThreePublicInputsPath;
let blindingFactor: bigint = BigInt(argv.blindingFactor);

let inputDataRaw = fs.readFileSync(inputDataPath);
let inputData: ProofOfAssetsInputFileShape = JSON.parse(inputDataRaw, jsonReviver);

let publicInputsRaw = fs.readFileSync(layerThreePublicInputsPath);
let publicInputs: string[] = JSON.parse(publicInputsRaw, jsonReviver);

let balanceSum = inputData.accountAttestations.reduce(
    (accumulator, currentValue) => currentValue.accountAttestations.balance + accumulator,
    0n
);

let com_calc = pedersen_commitment(balanceSum, blindingFactor);
let com_circuit = dechunk_to_point(publicInputs.map(i => BigInt(i)));

assert.ok(
    point_equal(com_calc, com_circuit),
);
