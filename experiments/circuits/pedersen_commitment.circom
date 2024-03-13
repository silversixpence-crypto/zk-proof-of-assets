pragma circom 2.0.1;

include "../git_modules/ed25519-circom/circuits/scalarmul.circom";
include "../git_modules/ed25519-circom/circuits/point-addition.circom";

// Calculates g^q * h^r
template PedersenCommitment() {
    signal input g[4][3];
    signal input h[4][3];

    signal input q[255];
    signal input r[255];

    signal output res[4][3];

    signal first[4][3];
    signal second[4][3];

    first <== ScalarMul()(q, g);
    second <== ScalarMul()(r, h);
    res <== PointAdd()(first, second);
}

component main = PedersenCommitment();
