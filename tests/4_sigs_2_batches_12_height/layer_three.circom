pragma circom 2.1.7;

include "../../circuits/layer_three.circom";

component main {public [merkle_root]} = LayerThree(2);
