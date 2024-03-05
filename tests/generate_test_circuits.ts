const fs = require('fs');
const path = require('path');
const parseArgs = require('minimist');

var argv = parseArgs(process.argv.slice(2), {
    alias: {
        num_sigs: ['num-sigs', 'n'],
        merkle_tree_height: ['tree-height', 'h'],

        // How many layer one & two proofs are done in parallel.
        layer_parallelism: ['parallelism', 'p'],
    },
    default: {
        num_sigs: 2,
        merkle_tree_height: 25, // Enough for anon set of size 33M.
        layer_parallelism: 1, // Only need more than 1 if you go beyond ~600 sigs.
    }
});

let num_sigs = argv.num_sigs;
let merkle_tree_height = argv.merkle_tree_height;
let parallelism: number = argv.layer_parallelism;

let dir = path.join(__dirname, num_sigs + "_sigs");
if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir);
}

let circuits = {
    one: `pragma circom 2.1.7;

include "../../circuits/layer_one.circom";

component main = LayerOne(${num_sigs});
`,

    two: `pragma circom 2.1.7;

include "../../circuits/layer_two.circom";

component main {public [merkle_root]} = LayerTwo(${num_sigs}, 25);
`,

    three: `pragma circom 2.1.7;

include "../../circuits/layer_three.circom";

component main = LayerThree(${parallelism});
`};

for (const [name, code] of Object.entries(circuits)) {
    let filepath = path.join(dir, "layer_" + name + ".circom");
    fs.writeFileSync(filepath, code);
}
