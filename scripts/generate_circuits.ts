/**
   Generates Circom code for the 3 layers, using CLI input value.

   It basically configures the input params for the 3 circuit layers.

   Use CLI like this:
   ```bash
   npx ts-node ./scripts/generate_circuits.ts \
                 --num-sigs <num_sigs_per_batch> \
                 --num-sigs-remainder <num_sigs_in_remainder_batch> \
                 --tree-height <merkle_tree_height> \
                 --parallelism <num_batches> \
                 --write-circuits-to <generated_circuits_dir> \
                 --circuits-library-relative-path <path_to_circuits_dir_from_generated_circuits_dir>
   ```
**/

const fs = require('fs');
const path = require('path');
const parseArgs = require('minimist');
const assert = require('assert');

var argv = parseArgs(process.argv.slice(2), {
    alias: {
        merkleTreeHeight: ['tree-height', 'h'],

        circuitsDir: ['write-circuits-to', 'o'],
        circuitsLib: ['circuits-library-relative-path', 'c'],

        // How many sigs per batch.
        numSigs: ['num-sigs', 'n'],

        // How many sigs in the last batch.
        numSigsRemainder: ['num-sigs-remainder', 'N'],

        // How many layer one & two proofs are done in parallel.
        layerParallelism: ['parallelism', 'p'],
    },
    default: {
        numSigs: 2,
        numSigsRemainder: 0,
        merkleTreeHeight: 25, // Enough for anon set of size 33M.
        circuitsDir: __dirname,
        layerParallelism: 1, // Only need more than 1 if you go beyond ~600 sigs.
    }
});

let numSigs: number = argv.numSigs;
let numSigsRemainder: number = argv.numSigsRemainder;
let merkleTreeHeight: number = argv.merkleTreeHeight;
let parallelism: number = argv.layerParallelism;
let circuitsDir: string = argv.circuitsDir;
let circuitsLib: string = argv.circuitsLib;

assert.ok(typeof numSigs === 'number');
assert.ok(typeof numSigsRemainder === 'number');
assert.ok(typeof merkleTreeHeight === 'number');
assert.ok(typeof parallelism === 'number');
assert.ok(typeof circuitsDir === 'string');
assert.ok(typeof circuitsLib === 'string');

if (!fs.existsSync(circuitsDir)) {
    fs.mkdirSync(circuitsDir);
}

let circuits = {
    one: `pragma circom 2.1.7;

include "${circuitsLib}/layer_one.circom";

component main = LayerOne(${numSigs});
`,

    two: `pragma circom 2.1.7;

include "${circuitsLib}/layer_two.circom";

component main {public [merkle_root]} = LayerTwo(${numSigs}, ${merkleTreeHeight});
`,

    three: `pragma circom 2.1.7;

include "${circuitsLib}/layer_three.circom";

component main = LayerThree(${parallelism});
`};

if (numSigsRemainder > 0) {
    let remainder_circuits = {
        one_remainder: `pragma circom 2.1.7;

include "${circuitsLib}/layer_one.circom";

component main = LayerOne(${numSigsRemainder});
`,

        two_remainder: `pragma circom 2.1.7;

include "${circuitsLib}/layer_two.circom";

component main {public [merkle_root]} = LayerTwo(${numSigsRemainder}, ${merkleTreeHeight});
`,
    }

    circuits = {
        ...circuits,
        ...remainder_circuits,
    }
}

for (const [name, code] of Object.entries(circuits)) {
    let filepath = path.join(circuitsDir, "layer_" + name + ".circom");
    fs.writeFileSync(filepath, code);
}
