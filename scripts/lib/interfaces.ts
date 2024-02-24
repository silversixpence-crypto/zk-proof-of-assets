import { Point } from '@noble/secp256k1';
import { interfaces } from 'mocha';

// Main input for the system.
export interface ProofOfAssetsInputFileShape {
    account_data: AccountData[],
    msg_hash: Uint8Array,
}

export interface Signature {
    r: bigint,
    s: bigint,
    r_prime: bigint,
    pubkey: Point,
}

// TODO rename to AccountAttestation or something
export interface AccountData {
    signature: Signature,
    wallet_data: WalletData,
}

export interface WalletData {
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

export interface Proofs {
    path_elements: bigint[][],
    path_indices: number[][],
}
