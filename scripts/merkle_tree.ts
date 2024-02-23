import { jsonReplacer, jsonReviver } from "./lib/json_serde";
import { ProofOfAssetsInputFileShape, WalletData, Proofs } from "./lib/interfaces";

const circomlibjs = require("circomlibjs");
const fs = require('fs');
const path = require('path');

// NOTE: picked this as the null field element arbitrarily
const NULL_NODE: bigint = 1n;

interface Leaf {
    address: bigint,
    balance: bigint,
    hash: bigint,
}

// Construct the Merkle tree and return all the data as a 2-dimensional array.
// The first element of the array are the leaf nodes, and the last element of the array is the root node.
async function build_tree(leaves: bigint[], height: number = 0, null_node = NULL_NODE): Promise<bigint[][]> {
    if (height === 0) {
        // Determine height automatically.
        height = Math.ceil(Math.log2(leaves.length)) + 1;
    }

    let required_leaves = 2 ** (height - 1);

    if (required_leaves < leaves.length) {
        throw new Error(`Height ${height} is not big enough for the amount of leaves ${leaves.length}`);
    }

    // Pad with nullNode to guarantee a full tree.
    if (leaves.length < required_leaves) {
        leaves = leaves.concat(Array(required_leaves - leaves.length).fill(null_node));
    }

    // It does not matter if the leaves are sorted or not, but this does offer some standardization.
    leaves.sort();

    const poseidon = await circomlibjs.buildPoseidon();
    const F = poseidon.F; // poseidon finite field

    let tree = [leaves];
    let cur_level = 0;

    while (tree[cur_level].length > 1) {
        let new_level = [];

        for (let i = 0; i < tree[cur_level].length; i += 2) {
            let left_child = tree[cur_level][i];
            let right_child = tree[cur_level][i + 1];

            let poseidonRes = poseidon([left_child, right_child]);
            let parent = F.toObject(poseidonRes);

            new_level.push(parent);
        }

        tree.push(new_level);
        cur_level++;
    }

    return tree;
}

function path_element_index(node_index: number) {
    if (node_index % 2 === 0) {
        return node_index + 1;
    } else {
        return node_index - 1;
    }
}

function path_index(node_index: number) {
    if (node_index % 2 === 0) {
        return 0;
    } else {
        return 1;
    }
}

function parent_node_index(node_index: number) {
    return Math.floor(node_index / 2);
}

function generate_proofs(tree: bigint[][], owned_leaves: Leaf[]): Proofs {
    let proofs: Proofs = {
        path_elements: [],
        path_indices: [],
    };

    let node_index = 0;

    for (let owned_leaf_index = 0; owned_leaf_index < owned_leaves.length; owned_leaf_index++) {
        let owned_leaf = owned_leaves[owned_leaf_index];
        let path_elements = [];
        let path_indices = [];

        for (let level = 0; level < tree.length - 1; level++) {
            if (level === 0) {
                // Find the owned leaf in the bottom layer of the tree.

                while (owned_leaf.hash != tree[0][node_index] && node_index <= tree[0].length) {
                    node_index++;
                }

                if (node_index === tree[0].length) {
                    throw new Error(`Cannot find owned leaf with address ${owned_leaf.address} in the tree`);
                }

                path_elements.push(tree[0][path_element_index(node_index)]);
                path_indices.push(path_index(node_index));
            } else {
                // Traverse the tree from bottom to top, adding all sibling nodes to the list.

                node_index = parent_node_index(node_index);
                path_elements.push(tree[level][path_element_index(node_index)]);
                path_indices.push(path_index(node_index));
            }
        }

        proofs.path_elements.push(path_elements);
        proofs.path_indices.push(path_indices);
    }

    return proofs;
}

async function convert_to_leaves(leaf_addresses: bigint[], leaf_balances: bigint[], owned_leaf_addresses: bigint[]) {
    let leaves: bigint[] = [];
    let owned_leaves: Leaf[] = [];

    const poseidon = await circomlibjs.buildPoseidon();
    const F = poseidon.F; // poseidon finite field

    for (let i = 0; i < leaf_addresses.length; i++) {
        let poseidonRes = poseidon([leaf_addresses[i], leaf_balances[i]]);
        let leaf = F.toObject(poseidonRes);

        leaves.push(leaf);

        for (let j = 0; j < owned_leaf_addresses.length; j++) {
            if (leaf_addresses[i] === owned_leaf_addresses[j]) {
                owned_leaves.push({
                    address: leaf_addresses[i],
                    balance: leaf_balances[i],
                    hash: leaf,
                });
                continue;
            }
        }
    }

    return {
        leaves,
        owned_leaves,
    };
}

var argv = require('minimist')(process.argv.slice(2), {
    alias: {
        anonymity_set: ['anonymity-set', 'a'],
        poa_input_data_path: ['poa-input-data', 'i'],
        output_dir: ['output-dir', 'o'],
        tree_height: ['height', 'd'],
    },
    default: {
        anonymity_set: path.join(__dirname, "../tests/anonymity_set.json"),
        poa_input_data_path: path.join(__dirname, "../tests/input_data_for_2_wallets.json"),
        output_dir: path.join(__dirname, "../tests"),
        tree_height: 0, // automatically determine height based on number of leaves
    }
});

let anonymity_set_path = argv.anonymity_set;
let poa_input_data_path = argv.poa_input_data_path;
let merkle_tree_path = path.join(argv.output_dir, "merkle_tree.json");
let merkle_root_path = path.join(argv.output_dir, "merkle_root.json");
let merkle_proofs_path = path.join(argv.output_dir, "merkle_proofs.json");
let height = argv.tree_height;

let anonymity_set_raw = fs.readFileSync(anonymity_set_path);
let poa_input_data_raw = fs.readFileSync(poa_input_data_path);

let anonymity_set: WalletData[] = JSON.parse(anonymity_set_raw, jsonReviver);
let poa_input_data: ProofOfAssetsInputFileShape = JSON.parse(poa_input_data_raw, jsonReviver);

convert_to_leaves(
    anonymity_set.map(a => a.address),
    anonymity_set.map(a => a.balance),
    poa_input_data.account_data.map(a => a.wallet_data.address),
).then(({ leaves, owned_leaves }) => {
    build_tree(leaves, height).then((tree) => {
        // https://stackoverflow.com/questions/29175877/json-stringify-throws-rangeerror-invalid-string-length-for-huge-objects
        let json =
            "[" +
            tree.map(i =>
                "[" +
                i.map(j =>
                    JSON.stringify(j,
                        (key, value) => typeof value === "bigint" ? value.toString() : value,
                    )).join(",")
                + "]"
            ).join(",") +
            "]";

        fs.writeFileSync(merkle_tree_path, json);

        let root = tree[tree.length - 1][0];
        json = JSON.stringify(root, jsonReplacer, 2);
        fs.writeFileSync(merkle_root_path, json);

        let proofs = generate_proofs(tree, owned_leaves);
        json = JSON.stringify(
            proofs,
            (key, value) => typeof value === "bigint" ? value.toString() : value,
            2
        );
        fs.writeFileSync(merkle_proofs_path, json);
    })
})

// ================================================================
// Some test data:

// Private keys (decimal) (from generate_test_input.ts)
// 66938844460645107025781008991556355714625654511665288941412380224408210845354,
// 11103745739792365897258682640621486163995830732847673942264532053458061009278,

// Private keys (hex)
// 0x93FE0B17EEEF03B57FE27AF49C1DADE41EA688B23108362E359E0447F1672EAA
// 0x188C7F53EFE3E1D5B9DD0EFB2B2D859A22F82895BBE5B8384620D44DC21EA17E

// Public keys (eth_address_dump) (hex)
// 0x4d1bce0a18161d4c1354e2f00ee711d24f1f4e87d6c81313ed6151ff5123876f288600a424a24a0ca72167f5ecc7287afb78f35be132de122ab31d1b971c6b7a
// 0xaa22a7b68bf99c433f9939c8c905ecf608033d96891c92ac858fd0e2d360a8d579880a09bc17dc6cc7f4654455d4c65b9ddaa4338c4e78cd7d1d8743d6db543b

// Compressed public keys (hex)
// 0x024d1bce0a18161d4c1354e2f00ee711d24f1f4e87d6c81313ed6151ff5123876f
// 0x03aa22a7b68bf99c433f9939c8c905ecf608033d96891c92ac858fd0e2d360a8d5

// Addresses (hex)
// 0x668e97bfd9851af354c0508d6c180ddc68244826
// 0x782a37Cc40a61789f80a96450d770ABA841c7EcD

// Addresses (dec)
// 585496983680464354843203206628328260164972202022
// 686020384476461118200129503363572918284147523277
