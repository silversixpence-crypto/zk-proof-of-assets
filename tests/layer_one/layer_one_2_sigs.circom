pragma circom 2.1.7;

include "../../circuits/layer_one.circom";

component main {public [pubkey]} = LayerOne(2);
