pragma circom 2.1.7;

include "../git_modules/circom-pairing/circuits/bn254/groth16.circom";
include "./eth.circom";
include "./merkle.circom";

template LayerTwo(num_sigs, merkle_tree_height) {
    // Number of dimensions needed to describe a point on an EC curve.
    var ec_dimension = 2;

    // Recommended number of registers for ECDSA verification.
    var num_registers = 4;

    // Recommended register bit length for ECDSA verification.
    var register_bit_length = 64;

    //////////////////////////////////////////////
    // Public inputs of layer one circuit.

    // Layer one only has a single hash as public input (hash of the pubkey x-coords)
    var layer_one_pub_inputs = 1;

    signal input pubkey_x_coord_hash;

    //////////////////////////////////////////////
    // G16 verification.

    // BN254 facts.
    var k = 6;

    // G16 verification key.
    signal input negalfa1xbeta2[6][2][k]; // e(-alfa1, beta2)
    signal input gamma2[2][2][k];
    signal input delta2[2][2][k];
    signal input IC[layer_one_pub_inputs+1][2][k];

    // G16 proof.
    signal input negpa[2][k];
    signal input pb[2][2][k];
    signal input pc[2][k];

    // G16 inputs.
    signal pub_input[layer_one_pub_inputs];
    pub_input[0] <== pubkey_x_coord_hash;

    signal verification_result <== verifyProof(layer_one_pub_inputs)(negalfa1xbeta2, gamma2, delta2, IC, negpa, pb, pc, pub_input);

    verification_result === 1;

    //////////////////////////////////////////////
    // Verify pubkeys hash match layer one public input.

    signal input pubkey[num_sigs][ec_dimension][num_registers];

    component hasher = Poseidon(num_sigs*num_registers);

    for (var i = 0; i < num_sigs; i++) {
        for (var j = 0; j < num_registers; j++) {
            // Hash x-coords of pubkeys.
            hasher.inputs[i*num_registers + j] <== pubkey[i][0][j];
        }
    }

    pubkey_x_coord_hash === hasher.out;

    //////////////////////////////////////////////
    // Convert pubkeys to Ethereum addresses.

    // 512 is what is required by FlattenPubkey.
    signal pubkey_bits[num_sigs][512];
    signal addresses[num_sigs];

    for (var i = 0; i < num_sigs; i++) {
        pubkey_bits[i] <== FlattenPubkey(register_bit_length, num_registers)(pubkey[i]);
        addresses[i] <== PubkeyToAddress()(pubkey_bits[i]);

        if (i > 0) {
            assert(addresses[i] > addresses[i-1]);
        }
    }

    //////////////////////////////////////////////
    // Merkle proof verification.

    // We only check the layers below the root.
    var levels = merkle_tree_height - 1;

    signal input merkle_root;
    signal input leaf_addresses[num_sigs];
    signal input leaf_balances[num_sigs];
    signal input path_elements[num_sigs][levels];
    signal input path_indices[num_sigs][levels];

    component leaf_hashers[num_sigs];
    signal leaves[num_sigs];

    for (var i = 0; i < num_sigs; i++) {
        addresses[i] === leaf_addresses[i];

        leaf_hashers[i] = Poseidon(2);
        leaf_hashers[i].inputs[0] <== leaf_addresses[i];
        leaf_hashers[i].inputs[1] <== leaf_balances[i];
        leaves[i] <== leaf_hashers[i].out;

        MerkleProofVerify(levels)(leaves[i], merkle_root, path_elements[i], path_indices[i]);
    }

    //////////////////////////////////////////////
    // Add balances.

    var sum = 0;

    for (var i = 0; i < num_sigs; i++) {
        sum += leaf_balances[i];
    }

    signal output balance_sum <== sum;
}

