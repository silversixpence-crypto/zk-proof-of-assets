pragma circom 2.0.3;

include "../git_modules/circom-pairing/circuits/bn254/groth16.circom";

component main = verifyProof(5);

// TODO manually link to input values and do:
// assert(groth16Verifier.out == 1);