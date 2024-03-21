const fs = require('fs');
const path = require('path');
const parseArgs = require('minimist');

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

let numSigs = argv.numSigs;
let numSigsRemainder = argv.numSigsRemainder;
let merkleTreeHeight = argv.merkleTreeHeight;
let parallelism: number = argv.layerParallelism;
let circuitsDir = argv.circuitsDir;
let circuitsLib = argv.circuitsLib;

// TODO ensure all the above values are the expected type

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
