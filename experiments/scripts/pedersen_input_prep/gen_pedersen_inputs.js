const utils = require('./utils');
const fs = require('fs');
const path = require('path');

const p = BigInt(2 ** 255) - BigInt(19);

const G = [
  15112221349535400772501151409588531511454012693041857206046113283949847762202n,
  46316835694926478169428394003475163141307993866256225615783033603165251855960n,
  1n,
  46827403850823179245072216630277197565144205554125654976674165829533817101731n,
];
const H = [
  33610936965734216034622052748864527785054979741013463956582067314415336407764n,
  39037926758455103342491841394431773648115673280860795116462000885017926418697n,
  44972472311651602601636560056538958210842501314939311016992875096561375476462n,
  25285931357802837959040485138497351343220742265312934020814563180777586254493n,
]

const q = 5n;
const r = 4869643893319708471955165214975585939793846505679808910535986866633137979160n;

////////////////////////////////////////////////
// Prepare curve points

const chunkG = [];
for (let i = 0; i < 4; i++) {
  chunkG.push(utils.chunkBigInt(G[i], BigInt(2 ** 85)));
}
for (let i = 0; i < 4; i++) {
  utils.pad(chunkG[i], 3);
}
console.log("G input", chunkG);

const chunkH = [];
for (let i = 0; i < 4; i++) {
  chunkH.push(utils.chunkBigInt(H[i], BigInt(2 ** 85)));
}
for (let i = 0; i < 4; i++) {
  utils.pad(chunkH[i], 3);
}
console.log("H input", chunkH);

////////////////////////////////////////////////
// Prepare scalars

const q_buf = utils.bigIntToLEBuffer(q);
const q_asBits = utils.pad(utils.buffer2bits(q_buf), 255);
// q_asBits.pop();
console.log("q input", q_asBits);

const r_buf = utils.bigIntToLEBuffer(r);
const r_asBits = utils.pad(utils.buffer2bits(r_buf), 255);
r_asBits.pop();
console.log("r input", r_asBits);

////////////////////////////////////////////////
// Write input file

const inputs = {
  g: chunkG,
  h: chunkH,
  q: q_asBits,
  r: r_asBits,
};

fs.writeFileSync(path.join(__dirname, "pedersen_inputs.json"), JSON.stringify(inputs, (_, v) => typeof v === 'bigint' ? v.toString() : v));

////////////////////////////////////////////////
// Calculate expected output here

const first = utils.point_mul(q, G);
for (let i = 0; i < 4; i++) {
  first[i] = utils.modulus(first[i], p);
}
console.log("g^q", first);

const second = utils.point_mul(r, H);
for (let i = 0; i < 4; i++) {
  second[i] = utils.modulus(second[i], p);
}
console.log("h^r", second);

const final = utils.point_add(first, second);
for (let i = 0; i < 4; i++) {
  final[i] = utils.modulus(final[i], p);
}
console.log("g^q * h^r", final);

