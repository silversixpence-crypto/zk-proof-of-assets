pragma circom 2.0.5;

include "../git_modules/batch-ecdsa/circuits/batch_ecdsa.circom";

component main {public [msghash]} = BatchECDSAVerifyNoPubkeyCheck(64, 4, 64);