import { Point } from '@noble/secp256k1';
import { interfaces } from 'mocha';

// Main input for the system.
export interface ProofOfAssetsInputFileShape {
    account_data: AccountAttestation[],
    msg_hash: Uint8Array,
}

export interface Signature {
    r: bigint,
    s: bigint,
    r_prime: bigint,
    pubkey: Point,
}

export interface AccountAttestation {
    signature: Signature,
    account_data: AccountData,
}

export interface AccountData {
    address: bigint,
    balance: bigint,
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

export interface Leaf {
    address: bigint,
    balance: bigint,
    hash: bigint,
}

export interface Proofs {
    leaves: Leaf[],
    path_elements: bigint[][],
    path_indices: number[][],
}
