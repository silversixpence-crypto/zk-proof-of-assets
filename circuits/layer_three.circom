pragma circom 2.1.7;

include "../git_modules/circom-pairing/circuits/bn254/groth16.circom";
include "../git_modules/ed25519-circom/circuits/scalarmul.circom";

template LayerThree(layer_two_count) {
    //////////////////////////////////////////////
    // Public inputs of layer two circuit.

    // Layer two has 2 public inputs: root of merkle tree, balance sum.
    var layer_two_pub_inputs = 2;

    // Balance sum of the addresses from layer two.
    // This is a public input of the layer two circuit.
    signal input balances[layer_two_count];

    signal input merkle_root;

    //////////////////////////////////////////////
    // G16 verification.

    // BN254 facts.
    var k = 6;

    // G16 verification key.
    signal input negalfa1xbeta2[layer_two_count][6][2][k]; // e(-alfa1, beta2)
    signal input gamma2[layer_two_count][2][2][k];
    signal input delta2[layer_two_count][2][2][k];
    signal input IC[layer_two_count][layer_two_pub_inputs+1][2][k];

    // G16 proof.
    signal input negpa[layer_two_count][2][k];
    signal input pb[layer_two_count][2][2][k];
    signal input pc[layer_two_count][2][k];

    // G16 inputs.
    signal pub_input[layer_two_count][layer_two_pub_inputs];

    signal verification_result[layer_two_count];

    for (var i = 0; i < layer_two_count; i++) {
        pub_input[i][0] <== balances[i];
        pub_input[i][1] <== merkle_root;

        verification_result[i] <== verifyProof(layer_two_pub_inputs)(negalfa1xbeta2[i], gamma2[i], delta2[i], IC[i], negpa[i], pb[i], pc[i], pub_input[i]);

        verification_result[i] === 1;
    }

    //////////////////////////////////////////////
    // Add balances.

    var sum = 0;

    for (var i = 0; i < layer_two_count; i++) {
        sum += balances[i];
    }

    signal balance_sum <== sum;

    //////////////////////////////////////////////
    // Pedersen commitment for balance sum.

    var num_coords = 4;
    var num_registers = 3;

    signal input ped_com_generator_g[num_coords][num_registers];
    signal input ped_com_generator_h[num_coords][num_registers];

    signal ped_com_secret[255] <== Num2Bits(255)(balance_sum);
    signal input ped_com_blinding_factor[255];

    signal output ped_com_result[num_coords][num_registers];

    signal first_exp[num_coords][num_registers];
    signal second_exp[num_coords][num_registers];

    first_exp <== ScalarMul()(ped_com_secret, ped_com_generator_g);
    second_exp <== ScalarMul()(ped_com_blinding_factor, ped_com_generator_h);
    ped_com_result <== PointAdd()(first_exp, second_exp);
}
