// Some of this code was taken from
// https://github.com/puma314/batch-ecdsa/blob/b512c651f497985a74858154e4a69bcdaf02443e/test/utils.ts

export function bigint_to_array(n: number, k: number, x: bigint) {
    let mod: bigint = 1n;
    for (var idx = 0; idx < n; idx++) {
        mod = mod * 2n;
    }

    let ret: bigint[] = [];
    var x_temp: bigint = x;
    for (var idx = 0; idx < k; idx++) {
        ret.push(x_temp % mod);
        x_temp = x_temp / mod;
    }

    return ret;
}

// bigendian
export function bigint_to_Uint8Array(x: bigint) {
    var ret: Uint8Array = new Uint8Array(32);
    for (var idx = 31; idx >= 0; idx--) {
        ret[idx] = Number(x % 256n);
        x = x / 256n;
    }
    return ret;
}

// bigendian
export function Uint8Array_to_bigint(x: Uint8Array) {
    var ret: bigint = 0n;
    for (var idx = 0; idx < x.length; idx++) {
        ret = ret * 256n;
        ret = ret + BigInt(x[idx]);
    }
    return ret;
}

// Taken from:
// https://github.com/yi-sun/circom-pairing/blob/107c316223a08ac577522c54edd81f0fc4c03130/test/test.ts
const hexes = Array.from({ length: 256 }, (v, i) =>
    i.toString(16).padStart(2, "0")
);
export function bytesToHex(uint8a: Uint8Array): string {
    // pre-caching chars could speed this up 6x.
    let hex = "";
    for (let i = 0; i < uint8a.length; i++) {
        hex += hexes[uint8a[i]];
    }
    return hex;
}

