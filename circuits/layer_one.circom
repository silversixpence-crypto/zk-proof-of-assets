pragma circom 2.1.7;

include "../git_modules/batch-ecdsa/circuits/batch_ecdsa.circom";
include "../node_modules/circomlib/circuits/poseidon.circom";

template LayerOne(num_sigs) {
    // Number of dimensions needed to describe a point on an EC curve.
    var ec_dimension = 2;

    // Recommended register bit length for ECDSA verification.
    var register_bit_length = 64;

    // Recommended number of registers for ECDSA verification.
    var num_registers = 4;

    // ECDSA signature values.
    signal input r[num_sigs][num_registers];
    signal input rprime[num_sigs][num_registers];
    signal input s[num_sigs][num_registers];
    signal input msghash[num_sigs][num_registers];
    signal input pubkey[num_sigs][ec_dimension][num_registers];

    // Verify ECDSA signatures.
    signal verification_result <== BatchECDSAVerifyNoPubkeyCheck(register_bit_length, num_registers, num_sigs)(r, rprime, s, msghash, pubkey);
    verification_result === 1;

    // Hash x-coords of pubkeys.
    component hasher = Poseidon(num_sigs*num_registers);
    for (var i = 0; i < num_sigs; i++) {
        for (var j = 0; j < num_registers; j++) {
            hasher.inputs[i*num_registers + j] <== pubkey[i][0][j];
        }
    }
    signal output pubkey_x_coord_hash <== hasher.out;

    // TODO need to verify the pubkeys are valid
}
