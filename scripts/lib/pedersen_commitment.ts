// Some code taken from https://github.com/Electron-Labs/ed25519-circom/blob/c9435c021384a74009c0b2ec2a5e863b2190e63b/test/utils.js

const fs = require('fs');
const path = require('path');
const bigintModArith = require('bigint-mod-arith');

////////////////////////////////////////////////
// Constants.

// See "Choice of curve" section in the Ed25519 DSA paper: https://link.springer.com/content/pdf/10.1007/s13389-012-0027-1.pdf
// More info here: https://crypto.stackexchange.com/questions/27392/base-point-in-ed25519
export const generator_g = [
    15112221349535400772501151409588531511454012693041857206046113283949847762202n,
    46316835694926478169428394003475163141307993866256225615783033603165251855960n,
    1n,
    46827403850823179245072216630277197565144205554125654976674165829533817101731n,
];

// Comes from taking the hash of generator_g: https://github.com/zkcrypto/bulletproofs/blob/a02837b737f956c5dec643c58040f8ea58f5efd6/src/generators.rs#L48-L49
// This must be the same as the one used in Bulletproofs so that we can interface with the DAPOL code.
export const generator_h = [
    33610936965734216034622052748864527785054979741013463956582067314415336407764n,
    39037926758455103342491841394431773648115673280860795116462000885017926418697n,
    44972472311651602601636560056538958210842501314939311016992875096561375476462n,
    25285931357802837959040485138497351343220742265312934020814563180777586254493n,
]

// Characteristic of the base field of the curve.
let p = BigInt(2 ** 255) - BigInt(19);

// Defines the Edwards curve equation x^2 + y^2 = 1 + dx^2y^2
let d = 37095705934669439343138083508754565189542113879843219016388785533085940283555n;

////////////////////////////////////////////////
// Utils.

function buffer2bits(buff: Buffer): bigint[] {
    const res = [];
    for (let i = 0; i < buff.length; i++) {
        for (let j = 0; j < 8; j++) {
            if ((buff[i] >> j) & 1) {
                res.push(1n);
            } else {
                res.push(0n);
            }
        }
    }
    return res;
}

function convertToEvenLength(hexInput: string): string {
    if (hexInput.length % 2 == 1) {
        return '0' + hexInput;
    }
    return hexInput;
}

function normalize(input: bigint[]): bigint[] {
    if (IsPowerOfTwo(input.length)) {
        input.push(0n);
    }
    return input;
}

function IsPowerOfTwo(x: number) {
    return (x & (x - 1)) == 0;
}

function bigIntToLEBuffer(x: bigint): Buffer {
    return Buffer.from(convertToEvenLength(x.toString(16)), 'hex').reverse()
}

function pad(x: bigint[], n: number): bigint[] {
    var total = n - x.length;
    for (var i = 0; i < total; i++) {
        x.push(0n);
    }
    return x;
}

// This function will give the right modulud as expected
function modulus(num: bigint, p: bigint): bigint {
    return ((num % p) + p) % p;
}

function bitsToBigInt(arr: number[]): bigint {
    let res = 0n;
    for (var i = 0; i < arr.length; i++) {
        res += (BigInt(2) ** BigInt(i)) * BigInt(arr[i]);
    }
    return res;
}

// This function will convert a bigInt into the chucks of Integers
function chunkBigInt(n: bigint, mod = BigInt(2 ** 51)): bigint[] {
    if (!n) return [0n];
    let arr = [];
    while (n) {
        arr.push(BigInt(modulus(n, mod)));
        n /= mod;
    }
    return arr;
}

// This function will perform point addition on elliptic curve 25519 to check point addition circom
function point_add(P: bigint[], Q: bigint[]): bigint[] {
    let A = modulus((P[1] - P[0]) * (Q[1] - Q[0]), p);
    let B = modulus((P[1] + P[0]) * (Q[1] + Q[0]), p);
    let C = modulus(BigInt(2) * P[3] * Q[3] * d, p);
    let D = modulus(BigInt(2) * P[2] * Q[2], p);

    let E = B - A;
    let F = D - C;
    let G = D + C;
    let H = B + A;

    return [E * F, G * H, F * G, E * H];
}

// This funciton will give the point multiplcation on EC 25519
function point_mul(s: bigint, P: bigint[]): bigint[] {
    let Q = [0n, 1n, 1n, 0n];
    while (s > 0) {
        if (s & 1n) {
            Q = point_add(Q, P);
        }
        P = point_add(P, P);
        s >>= 1n;
    }
    return Q;
}

function dechunk(x: bigint[], mod = BigInt(2 ** 51)): bigint {
    let sum = 0n;
    for (let i = 0; i < x.length; i++) {
        sum += (mod ** BigInt(i)) * x[i];
    }
    return sum;
}

export function point_equal(P: bigint[], Q: bigint[]): boolean {
    //  x1 / z1 == x2 / z2  <==>  x1 * z2 == x2 * z1
    if (modulus((P[0] * Q[2] - Q[0] * P[2]), p) != 0n) {
        return false
    }
    if (modulus((P[1] * Q[2] - Q[1] * P[2]), p) != 0n) {
        return false
    }
    return true
}

function point_compress(P: bigint[]): bigint[] {
    const zinv = bigintModArith.modInv(P[2], p);
    let x = modulus(P[0] * zinv, p);
    let y = modulus(P[1] * zinv, p);
    const inter = y | ((x & 1n) << 255n)
    return buffer2bits(bigIntToLEBuffer(inter));
}

////////////////////////////////////////////////
// Prepare generator points as snark input.

export const generator_g_formatted: bigint[][] = [];
for (let i = 0; i < 4; i++) {
    generator_g_formatted.push(chunkBigInt(generator_g[i], BigInt(2 ** 85)));
}
for (let i = 0; i < 4; i++) {
    pad(generator_g_formatted[i], 3);
}

export const generator_h_formatted: bigint[][] = [];
for (let i = 0; i < 4; i++) {
    generator_h_formatted.push(chunkBigInt(generator_h[i], BigInt(2 ** 85)));
}
for (let i = 0; i < 4; i++) {
    pad(generator_h_formatted[i], 3);
}

////////////////////////////////////////////////
// Format scalars.

export function format_scalar_power(k: bigint) {
    // This LE is a bit misleading, see:
    // https://github.com/silversixpence-crypto/zk-proof-of-assets/issues/38#issuecomment-1995667384
    const k_buf = bigIntToLEBuffer(k);
    const k_asBits = pad(buffer2bits(k_buf), 255);

    // The reason we have to check this is because bigIntToLEBuffer returns a byte array,
    // and when this is converted to bits with buffer2bits it will have a length that is a multiple of 8.
    // If bigIntToLEBuffer(k).length == 32 (256 / 8) then k_asBits.length == 256, so we need to shave off a bit to get to 255
    // else if bigIntToLEBuffer(k).length < 32 then k_asBits.length <= 248, so the padding will make it length 255
    if (k_asBits.length === 256) {
        k_asBits.pop();
    }

    return k_asBits;
}

////////////////////////////////////////////////
// Calculate Pedersen commitment.

export function pedersen_commitment(secret: bigint, blinding_factor: bigint): bigint[] {
    const first = point_mul(secret, generator_g);
    for (let i = 0; i < 4; i++) {
        first[i] = modulus(first[i], p);
    }
    // console.log("g^q", first);

    const second = point_mul(blinding_factor, generator_h);
    for (let i = 0; i < 4; i++) {
        second[i] = modulus(second[i], p);
    }
    // console.log("h^r", second);

    const final = point_add(first, second);
    for (let i = 0; i < 4; i++) {
        final[i] = modulus(final[i], p);
    }
    // console.log("g^q * h^r", final);

    return final;
}

////////////////////////////////////////////////
// Converting g16 signal data to an Edwards point.

export function dechunk_to_point(g16_signal: bigint[]): bigint[] {
    const chunks = [];
    for (let i = 0; i < 4; i++) {
        chunks.push(g16_signal.slice(3 * i, 3 * i + 3));
    }

    const dechunked = [];
    for (let i = 0; i < 4; i++) {
        dechunked.push(dechunk(chunks[i], BigInt(2 ** 85)));
    }

    return dechunked;
}
