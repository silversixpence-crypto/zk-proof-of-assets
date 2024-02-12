pragma circom 2.1.7;

include "../git_modules/batch-ecdsa/circuits/batch_ecdsa.circom";

template LayerOne(num_sigs) {
    var register_bit_length = 64;
    var num_registers = 4;

    signal input r[num_sigs][num_registers];
    signal input rprime[num_sigs][num_registers];
    signal input s[num_sigs][num_registers];
    signal input msghash[num_sigs][num_registers];
    signal input pubkey[num_sigs][2][num_registers];

    signal verification_result <== BatchECDSAVerifyNoPubkeyCheck(register_bit_length, num_registers, num_sigs)(r, rprime, s, msghash, pubkey);

    verification_result === 1;
}
