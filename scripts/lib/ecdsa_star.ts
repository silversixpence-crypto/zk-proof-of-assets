import { Uint8Array_to_bigint, bigint_to_Uint8Array } from "./utils";
import { EcdsaSignature, EcdsaStarSignature } from "./interfaces";
import * as secp from "@noble/secp256k1";

// Calculates a modulo b
export function mod(a: bigint, b: bigint = secp.CURVE.P): bigint {
    const result = a % b;
    return result >= 0n ? result : b + result;
}

// Inverses number over modulo
export function invert(number: bigint, modulo: bigint = secp.CURVE.P): bigint {
    if (number === 0n || modulo <= 0n) {
        throw new Error(`invert: expected positive integers, got n=${number} mod=${modulo}`);
    }

    // Eucledian GCD https://brilliant.org/wiki/extended-euclidean-algorithm/
    let a = mod(number, modulo);
    let b = modulo;
    let x = 0n, y = 1n, u = 1n, v = 0n;

    while (a !== 0n) {
        const q = b / a;
        const r = b % a;
        const m = x - u * q;
        const n = y - v * q;
        b = a, a = r, x = u, y = v, u = m, v = n;
    }
    const gcd = b;
    if (gcd !== 1n) throw new Error('invert: does not exist');

    return mod(x, modulo);
}

// computing v = r_i' in R_i = (r_i, r_i')
export function construct_r_prime(r: bigint, s: bigint, pubkey: secp.Point, msg_hash: Uint8Array): bigint {
    const { n } = secp.CURVE;

    var msg_hash_bigint: bigint = Uint8Array_to_bigint(msg_hash);

    var p_1 = secp.Point.BASE.multiply(mod(msg_hash_bigint * invert(s, n), n));
    var p_2 = pubkey.multiply(mod(r * invert(s, n), n));
    var p_res = p_1.add(p_2);

    return p_res.y;
}

function formatHex(str: string): string {
    if (str.startsWith("0x")) {
        str = str.slice(2);
    }
    return str;
}

function hexToBytes(hex: string, endian: string = "big"): Uint8Array {
    if (typeof hex !== "string") {
        throw new TypeError("hexToBytes: expected string, got " + typeof hex);
    }

    hex = formatHex(hex);
    if (hex.length % 2)
        throw new Error("hexToBytes: received invalid unpadded hex");

    const array = new Uint8Array(hex.length / 2);

    for (let i = 0; i < array.length; i++) {
        let j = 0;

        if (endian === "big") j = i * 2;
        else j = (array.length - 1 - i) * 2;

        const hexByte = hex.slice(j, j + 2);
        if (hexByte.length !== 2) throw new Error("Invalid byte sequence");

        const byte = Number.parseInt(hexByte, 16);
        if (Number.isNaN(byte) || byte < 0)
            throw new Error("Invalid byte sequence");

        array[i] = byte;
    }

    return array;
}

export function ecdsaStarFromEcdsa(ecdsa: EcdsaSignature): EcdsaStarSignature {
    if (ecdsa.v != 27 && ecdsa.v != 28) {
        throw new Error(`Invalid ECDSA 'v' value ${ecdsa.v} (must be 27 or 28)`);
    }

    let msghash = hexToBytes(ecdsa.msghash);
    let s = Uint8Array_to_bigint(hexToBytes(ecdsa.s));
    let r = Uint8Array_to_bigint(hexToBytes(ecdsa.r));
    let sig = new secp.Signature(r, s);

    let pubkey = secp.Point.fromSignature(ecdsa.msghash.substring(2), sig, ecdsa.v == 27 ? 0 : 1);
    var r_prime: bigint = construct_r_prime(r, s, pubkey, msghash);

    return { r, s, r_prime, pubkey, msghash };
}
