// copied from https://github.com/sethhrbek/heyanoun/blob/c043243493710109cb1d0f47daaf1015e908b1b4/circuits/circuits/daddy.circom

pragma circom 2.0.6;
include "../git_modules/circom-ecdsa/circuits/ecdsa.circom";

template SignatureVerification(n, k) {
    // public inputs
    signal input msghash[k];

    // Private inputs
    signal input signatureR[k];
    signal input signatureS[k];
    signal input pubkey[2][k]; // Public key is a 2-element array of 4 64-bit chunks (256 bits each)

    // Verify the signature is valid
    component ecdsaVerify = ECDSAVerifyNoPubkeyCheck(n, k);
    ecdsaVerify.r <== signatureR;
    ecdsaVerify.s <== signatureS;
    ecdsaVerify.pubkey <== pubkey;
    ecdsaVerify.msghash <== msghash;

    // Final result
    signal output verificationResult;
    verificationResult <== ecdsaVerify.result;
}

component main { public [ msghash ] } = SignatureVerification(64, 4);