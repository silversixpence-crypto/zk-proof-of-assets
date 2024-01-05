pragma circom 2.0.2;

include "../git_modules/keccak256-circom/circuits/keccak.circom";

template MyKeccak() {
    var n = 32;
    var m = 256;

    signal input preimagebits[n];
    signal input hashbits[m];

    component keccak256 = Keccak(n, m);

    for (var j = 0; j < n; j++) {
        keccak256.in[j] <== preimagebits[j];
    }

    for (var j = 0; j < m; j++) {
        assert(hashbits[j] == keccak256.out[j]);
    }
}

component main = MyKeccak();