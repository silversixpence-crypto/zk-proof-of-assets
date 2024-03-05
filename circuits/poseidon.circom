// Code taken from
// https://github.com/succinctlabs/telepathyx/blob/85469677e7afdba282dc6959a64c53ad8922b244/circuits/poseidon.circom

pragma circom 2.1.7;

include "../node_modules/circomlib/circuits/poseidon.circom";

template PoseidonSponge(length) {
    signal input inputs[length];
    signal output out;

    var round_length_max = 16;
    var num_rounds = length \ round_length_max;
    var round_length = round_length_max;
    var last_round_length = round_length_max;
    var out_length = 1;

    if (length % round_length_max > 0) {
        num_rounds++;
        last_round_length = length % round_length_max;
    }

    component hashers[num_rounds];

    for (var i = 0; i < num_rounds; i++) {
        if (i == num_rounds - 1) {
            round_length = last_round_length;
            out_length = 2;
        }

        hashers[i] = PoseidonEx(round_length, out_length);

        for (var j = 0; j < round_length; j++) {
            hashers[i].inputs[j] <== inputs[i * round_length + j];
        }

        if (i == 0) {
            hashers[i].initialState <== 0;
        } else {
            hashers[i].initialState <== hashers[i-1].out[0];
        }
    }

    out <== hashers[num_rounds - 1].out[1];
}

