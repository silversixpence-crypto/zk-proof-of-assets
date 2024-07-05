const { hashPersonalMessage, ecsign } = require("@ethereumjs/util");
const { SECP256K1_N } = require("./config");
const elliptic = require("elliptic");
const ec = new elliptic.ec("secp256k1");
const BN = require("bn.js");
const { splitToRegisters, registersToHex } = require("./utils");
const fs = require("fs");
const { getPointPreComputes } = require("./point-cache");

const privKey = BigInt(
  "0xf5b552f608f5b552f608f5b552f6082ff5b552f608f5b552f608f5b552f6082f"
);

const path = require('path');

const prove = async () => {
  const msgHash = hashPersonalMessage(Buffer.from("hello world"));

  const pubKey = ec.keyFromPrivate(privKey.toString(16)).getPublic();

  const { v, r, s } = ecsign(msgHash, privKey);

  const isYOdd = (v - BigInt(27)) % BigInt(2);
  const rPoint = ec.keyFromPublic(
    ec.curve.pointFromX(new BN(r), isYOdd).encode("hex"),
    "hex"
  );

  // Get the group element: -(m * r^−1 * G)
  const rInv = new BN(r).invm(SECP256K1_N);

  // w = -(r^-1 * msg)
  const w = rInv.mul(new BN(msgHash)).neg().umod(SECP256K1_N);
  // U = -(w * G) = -(r^-1 * msg * G)
  const U = ec.curve.g.mul(w);

  // T = r^-1 * R
  const T = rPoint.getPublic().mul(rInv);

  console.log("Calculating point cache...");
  console.time("Point cache calculation");
  const TPreComputes = getPointPreComputes(T);
  console.timeEnd("Point cache calculation");

  const input = {
    TPreComputes,
    U: [splitToRegisters(U.x), splitToRegisters(U.y)],
    s: [splitToRegisters(s.toString("hex"))]
  };

  // console.log("Proving...");
  // const { publicSignals, proof } = await snarkJs.groth16.fullProve(
  //   input,
  //   "build/ecdsa_verify/build_ecdsa_verify_js/build_ecdsa_verify.wasm",
  //   ZKEY_PATH
  // );

  // const outputPubkeyX = registersToHex(publicSignals.slice(0, 4).reverse());
  // const outputPubkeyY = registersToHex(publicSignals.slice(4, 8).reverse());
  // const outputPubKey = `${outputPubkeyX}${outputPubkeyY}`;

  // if (`04${outputPubKey}` === pubKey.encode("hex")) {
  //   console.log("Success!");
  //   console.timeEnd("Full proof generation");
  // } else {
  //   console.log("Output public key doesn't match expected public key");
  // }

  // // Now, verify the proof
  // await verify(proof, publicSignals);

var filename = "l1_input.json";
var filePath = path.join(__dirname, filename);
  const json = JSON.stringify(input, (_, v) => typeof v === 'bigint' ? v.toString() : v)
  fs.writeFileSync(filePath, json);
};

prove();
