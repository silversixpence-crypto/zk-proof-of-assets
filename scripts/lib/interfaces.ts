import { Point } from '@noble/secp256k1';
import { interfaces } from 'mocha';

export interface Signature {
    r: bigint,
    s: bigint,
    r_prime: bigint,
    pubkey: Point,
}

export interface WalletData {
    signature: Signature,
    address: bigint,
    balance: bigint,
}

export interface InputFileShape {
    wallet_data: WalletData[],
    msg_hash: Uint8Array,
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

