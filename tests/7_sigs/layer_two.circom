pragma circom 2.1.7;

include "../../circuits/layer_two.circom";

component main {public [merkle_root]} = LayerTwo(7, 25);
