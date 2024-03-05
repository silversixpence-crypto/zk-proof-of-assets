import { jsonReplacer, jsonReviver } from "./lib/json_serde";
import { ProofOfAssetsInputFileShape, AccountData, Proofs, Leaf } from "./lib/interfaces";

const circomlibjs = require("circomlibjs");
const fs = require('fs');
const path = require('path');
const JSONStream = require("JSONStream");

// ================================================================
// Tree building.

// NOTE: picked this as the null field element arbitrarily
const NULL_NODE: bigint = 1n;

// Construct the Merkle tree and return all the data as a 2-dimensional array.
// The first element of the array are the leaf nodes, and the last element of the array is the root node.
async function build_tree(poseidon: any, field: any, leaves: bigint[], height: number = 0, null_node = NULL_NODE): Promise<bigint[][]> {
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

    // It does not matter if the leaves are sorted or not, but this does offer some standardization,
    // and may make debugging easier.
    leaves.sort();

    let tree = [leaves];
    let cur_level = 0;

    while (tree[cur_level].length > 1) {
        let new_level = [];

        for (let i = 0; i < tree[cur_level].length; i += 2) {
            let left_child = tree[cur_level][i];
            let right_child = tree[cur_level][i + 1];

            let poseidonRes = poseidon([left_child, right_child]);
            let parent = field.toObject(poseidonRes);

            new_level.push(parent);
        }

        tree.push(new_level);
        cur_level++;
    }

    return tree;
}

// ================================================================
// Proofs.

// Node indexing starts at 0, so left nodes are at '% 2 === 0' and right nodes at '% 2 === 1'.
function path_element_index(node_index: number) {
    if (node_index % 2 === 0) {
        return node_index + 1;
    } else {
        return node_index - 1;
    }
}

// Node indexing starts at 0, so left nodes are at '% 2 === 0' and right nodes at '% 2 === 1'.
function path_index(node_index: number) {
    if (node_index % 2 === 0) {
        return 0;
    } else {
        return 1;
    }
}

// Parent layer is always half the number of nodes because we have a full tree.
function parent_node_index(node_index: number) {
    return Math.floor(node_index / 2);
}

async function verify_merkle_proof(poseidon: any, field: any, root: bigint, leaf: bigint, path_elements: bigint[], path_indices: number[]): Promise<boolean> {
    if (path_elements.length != path_indices.length) {
        throw new Error(`[leaf: ${leaf}] Length of path_elements array ${path_elements.length} should equal length of path_indices array ${path_indices.length}`);
    }

    let hash: bigint = 0n;

    for (let level = 0; level < path_elements.length; level++) {
        if (path_indices[level] === 0) {
            var left = level === 0 ? leaf : hash;
            var right = path_elements[level];
        } else {
            var left = path_elements[level];
            var right = level === 0 ? leaf : hash;
        }

        let poseidonRes = poseidon([left, right]);
        hash = field.toObject(poseidonRes);
    }

    return hash === root;
}

async function generate_proofs(poseidon: any, field: any, tree: bigint[][], owned_leaves: Leaf[]): Promise<Proofs> {
    let proofs: Proofs = {
        leaves: [],
        path_elements: [],
        path_indices: [],
    };

    proofs.leaves = owned_leaves;

    let node_index = 0;

    for (let owned_leaf_index = 0; owned_leaf_index < owned_leaves.length; owned_leaf_index++) {
        let owned_leaf = owned_leaves[owned_leaf_index];
        let path_elements: bigint[] = [];
        let path_indices: number[] = [];

        // '-1' 'cause we don't need to add a path_element/path_index for the root node, which is at the top.
        for (let level = 0; level < tree.length - 1; level++) {
            // Traverse the tree from bottom to top, adding all sibling nodes to the path_elements array.

            if (level === 0) {
                // Find the owned leaf in the bottom layer of the tree.
                node_index = tree[0].indexOf(owned_leaf.hash);

                if (node_index === -1) {
                    throw new Error(`Cannot find owned leaf with address ${owned_leaf.address} in the tree`);
                }
            } else {
                node_index = parent_node_index(node_index);
            }

            path_elements.push(tree[level][path_element_index(node_index)]);
            path_indices.push(path_index(node_index));
        }

        let root = tree[tree.length - 1][0];
        let proof_is_good = await verify_merkle_proof(poseidon, field, root, owned_leaf.hash, path_elements, path_indices);
        if (!proof_is_good) {
            console.log("ERROR Merkle proof failed to verify");
            console.log("    leaf: ", owned_leaf);
            console.log("    root: ", root);
            console.log("    path_elements: ", path_elements);
            console.log("    path_indices: ", path_indices);
            throw new Error("Merkle proof failed to verify");
        }

        proofs.path_elements.push(path_elements);
        proofs.path_indices.push(path_indices);
    }

    return proofs;
}

// ================================================================

// Convert account data into leaf nodes by hashing address and balance.
async function convert_to_leaves(poseidon: any, field: any, account_data: AccountData[]): Promise<Leaf[]> {
    let leaves: Leaf[] = [];

    for (let i = 0; i < account_data.length; i++) {
        let address = account_data[i].address;
        let balance = account_data[i].balance;

        let poseidon_result = poseidon([address, balance]);
        let hash = field.toObject(poseidon_result);

        leaves.push({
            address,
            balance,
            hash,
        });
    }

    return leaves;
}

// ================================================================
// Writing large json objects.

// NOTE not working, so is commented out.

// https://stackoverflow.com/questions/29175877/json-stringify-throws-rangeerror-invalid-string-length-for-huge-objects
// function write_large_object(large_object: any, path_to_write_to: string) {
//     var transformStream = JSONStream.stringify();
//     var outputStream = fs.createWriteStream(path_to_write_to);
//     transformStream.pipe(outputStream);
//     large_object.forEach(transformStream.write);
//     transformStream.end();

//     outputStream.on(
//         "finish",
//         function handleFinish() {
//             console.log("Done writing large object");
//         }
//     );
// }

// ================================================================
// Execution flow.

var argv = require('minimist')(process.argv.slice(2), {
    alias: {
        anonymity_set: ['anonymity-set', 'a'],
        poa_input_data_path: ['poa-input-data', 'i'],
        output_dir: ['output-dir', 'o'],
        tree_height: ['height', 'd'],
    },
    default: {
        anonymity_set: path.join(__dirname, "../tests/anonymity_set.json"),
        poa_input_data_path: path.join(__dirname, "../tests/input_data_for_32_accounts.json"),
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

let anonymity_set: AccountData[] = JSON.parse(anonymity_set_raw, jsonReviver);
let poa_input_data: ProofOfAssetsInputFileShape = JSON.parse(poa_input_data_raw, jsonReviver);

async function main() {
    const poseidon = await circomlibjs.buildPoseidon();
    const field = poseidon.F; // poseidon finite field

    let leaves = await convert_to_leaves(poseidon, field, anonymity_set);
    let owned_leaves = await convert_to_leaves(poseidon, field, poa_input_data.account_data.map(a => a.account_data));
    let tree = await build_tree(poseidon, field, leaves.map(l => l.hash), height);

    // NOTE not working, so is commented out.
    // https://stackoverflow.com/questions/29175877/json-stringify-throws-rangeerror-invalid-string-length-for-huge-objects
    // let json =
    //     "[" +
    //     tree.map(i =>
    //         "[" +
    //         i.map(j =>
    //             JSON.stringify(j,
    //                 (key, value) => typeof value === "bigint" ? value.toString() : value,
    //             )).join(",")
    //         + "]"
    //     ).join(",") +
    //     "]";

    // fs.writeFileSync(merkle_tree_path, json);
    // let tree_string = tree.map(level => level.map(node => node.toString()));
    // write_large_object(tree_string, merkle_tree_path);

    let root = tree[tree.length - 1][0];
    let json = JSON.stringify(root, jsonReplacer, 2);
    fs.writeFileSync(merkle_root_path, json);

    let proofs: Proofs = await generate_proofs(poseidon, field, tree, owned_leaves);
    json = JSON.stringify(
        proofs,
        jsonReplacer,
        2
    );
    fs.writeFileSync(merkle_proofs_path, json);
}

main();

// ================================================================
// Some test data for converting private keys to Ethereum addresses.

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
