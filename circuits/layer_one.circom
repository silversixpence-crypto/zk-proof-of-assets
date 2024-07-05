pragma circom 2.1.7;

include "./ecdsa_verify.circom";
include "./poseidon.circom";

template LayerOne(num_sigs) {
    // Number of dimensions needed to describe a point on an EC curve.
    var ec_dimension = 2;

    // Recommended register bit length for ECDSA verification.
    // Referred to as 'n' in the libraries.
    var register_bit_length = 64;

    // Recommended number of registers for ECDSA verification.
    // Referred to as 'k' in the libraries.
    var num_registers = 4;

    //////////////////////////////////////////////
    // ECDSA signature values.

    signal input s[num_sigs][num_registers];
    signal input T_pre_computes[num_sigs][32][256][2][4]; // T = r^-1 * R
    signal input U[num_sigs][ec_dimension][num_registers]; // -(m * r^-1 * G)

    signal input pubkey_in[num_sigs][ec_dimension][num_registers];
    signal pubkey[num_sigs][ec_dimension][num_registers];

    //////////////////////////////////////////////
    // Verify ECDSA signatures.

    // Note that there is no need to verify the pubkey because in
    // layer 2 it is converted to an Ethereum address, so if the
    // pubkey is invalid then so is the address.

    assert(num_sigs > 0);

    for (var i = 0; i < num_sigs; i++) {
        pubkey[i] <== ECDSAVerify(register_bit_length, num_registers)
            (s[i], T_pre_computes[i], U[i]);

        pubkey_in[i] === pubkey[i];
    }

    //////////////////////////////////////////////
    // Hash x-coords of pubkeys.

    component hasher = PoseidonSponge(num_sigs * num_registers);

    for (var i = 0; i < num_sigs; i++) {
        for (var j = 0; j < num_registers; j++) {
            // The x-coord lives at position 0.
            hasher.inputs[i * num_registers + j] <== pubkey[i][0][j];
        }
    }

    signal output pubkey_x_coord_hash <== hasher.out;

    //////////////////////////////////////////////
    // Hash T pre-computes

    component hasher2 = PoseidonSponge(num_sigs*32*256*2*4);

    for (var i = 0; i < num_sigs; i++) {
        for (var j = 0; j < 32; j++) {
            for (var k = 0; k < 256; k++) {
                for (var l = 0; l < 2; l++) {
                    for (var m = 0; m < 4; m++) {
                        hasher2.inputs[32*256*2*4*i + 256*2*4*j + 2*4*k + 4*l + m] <== T_pre_computes[i][j][k][l][m];
                    }
                }
            }
        }
    }

    signal input T_pre_computes_hash;
    T_pre_computes_hash === hasher2.out;
}
