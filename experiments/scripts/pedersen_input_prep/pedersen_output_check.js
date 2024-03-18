const utils = require('./utils');
const assert = require('assert');

// g^q * h^r
const output_raw = [
  "33802386337363135775523188",
  "23778182224651075695164659",
  "32498108452197444803201749",
  "35073949349630251726389439",
  "21198364664335867424021210",
  "23624493221089394528664359",
  "14161132945590533819337322",
  "17300377636736184101190813",
  "28459224501622577720113438",
  "1033866630276700443169621",
  "10058039175119990249603519",
  "15957773885913281862436939"
];

// g^q
// const output_raw = [
//   "34103906136500385091886334",
//   "2640804598686808970246632",
//   "9889199677520363578852026",
//   "32152069506342088431876038",
//   "13641214720527187728701581",
//   "5568504303545746646377312",
//   "1592599282780903627174334",
//   "5420831710890215399773474",
//   "3518447608753656573655964",
//   "34820262220270123517184146",
//   "11671690115604923287441884",
//   "27456176526510792991967991"
// ];

const output = output_raw.map(n => BigInt(n));

// g^q * h^r
const expected_output = [
  37265365969786020775905420635296558667377843363697089491268621263348662982968n,
  19918088020382620484898381577491593815929231710243946334400286158202769470154n,
  31159927823477228180874415041051045889480209716426176898820219283387381240684n,
  47079230722737970294378002000658448476925929131576789322759010697112857187123n
];

// g^q
// const expected_output = [
//   48587335896702516630025626387996632990217527701313511062579507721283610445974n,
//   8188740530626043362754002446144313297508373826931960925228032242803442486117n,
//   38552943002898238013538894255665090035369473846596139910480881681416636171415n,
//   56801903193622011524169812971252101676517371497990589073776552862250959924075n
// ];

const chunk = [];
for (let i = 0; i < 4; i++) {
  chunk.push(output.slice(3 * i, 3 * i + 3));
}

const dechunkedWt = [];
for (let i = 0; i < 4; i++) {
  dechunkedWt.push(utils.dechunk(chunk[i], BigInt(2 ** 85)));
}
console.log(dechunkedWt);

assert.ok(
  utils.point_equal(expected_output, dechunkedWt),
);