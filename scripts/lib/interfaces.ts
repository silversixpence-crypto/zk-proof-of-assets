import { Point } from '@noble/secp256k1';
import { interfaces } from 'mocha';

// Main input for the system.
export interface ProofOfAssetsInputFileShape {
    accountAttestations: AccountAttestation[],
}

export interface EcdsaSignature {
    v: number, // must be 27 or 28
    r: string,
    s: string,
    msghash: string,
}

export interface EcdsaStarSignature {
    r: bigint,
    s: bigint,
    r_prime: bigint,
    pubkey: Point,
    msghash: Uint8Array,
}

export interface AccountAttestation {
    signature: EcdsaStarSignature,
    accountData: AccountData,
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
    pubInput: bigint[],
}

export interface Leaf {
    address: bigint,
    balance: bigint,
    hash: bigint,
}

// TODO change the name here to MerkleProofs
export interface Proofs {
    leaves: Leaf[],
    path_elements: bigint[][],
    path_indices: number[][],
}
