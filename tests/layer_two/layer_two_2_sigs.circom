pragma circom 2.1.7;

include "../../circuits/layer_two.circom";

component main {public [root]} = LayerTwo(2, 24);
