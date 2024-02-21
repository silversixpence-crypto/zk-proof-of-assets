import { Point } from '@noble/secp256k1';

export interface SignaturesFileShape {
    signatures: Signature[],
    msg_hash: Uint8Array,
}

export interface Signature {
    r: bigint,
    s: bigint,
    r_prime: bigint,
    pubkey: Point,
}

export interface Groth16ProofAsInput {
    gamma2: number[][][],
    delta2: number[][][],
    negalfa1xbeta2: number[][][],
    IC: number[][][],
    negpa: number[][][],
    pb: number[][][],
    pc: number[][],
    pubInput: number[],
}

