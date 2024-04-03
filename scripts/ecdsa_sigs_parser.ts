// https://docs.ethers.org/v6/api/crypto/#SigningKey_recoverPublicKey

import * as ethers from "ethers";
import { AccountAttestation, EcdsaSignature, EcdsaStarSignature, ProofOfAssetsInputFileShape } from "./lib/interfaces";
import { jsonReplacer } from "../scripts/lib/json_serde";
import { ecdsa_star_from_ecdsa } from "./lib/ecdsa_star";

const fs = require('fs');
const assert = require('assert');

interface SignatureData {
    address: string,
    balance: string,
    signature: EcdsaSignature,
}

var argv = require('minimist')(process.argv.slice(2), {
    alias: {
        signaturesPath: ['signatures', 's'],
        outputPath: ['output-path', 'o'],
    },
});

let signaturesPath = argv.signaturesPath;
let outputPath = argv.outputPath;

fs.readFile(signaturesPath, function read(err: any, jsonIn: any) {
    if (err) {
        throw err;
    }

    let sigsInputData: SignatureData[] = JSON.parse(jsonIn);
    let num_sigs = sigsInputData.length;

    let accountAttestations: AccountAttestation[] = sigsInputData.map(sigInputData => {
        let ethers_ecdsaSig = ethers.Signature.from(sigInputData.signature);
        let pubkey = ethers.SigningKey.recoverPublicKey(sigInputData.signature.msghash, ethers_ecdsaSig)
        let addressFromEcdsa = ethers.computeAddress(pubkey);

        let ecdsaSig: EcdsaSignature = {
            r: ethers_ecdsaSig.r,
            s: ethers_ecdsaSig.s,
            v: ethers_ecdsaSig.v,
            msghash: sigInputData.signature.msghash,
        }
        let ecdsaStarSig = ecdsa_star_from_ecdsa(ecdsaSig);
        let addressFromEcdsaStar = ethers.computeAddress("0x" + ecdsaStarSig.pubkey.toHex());

        assert(addressFromEcdsa == sigInputData.address);
        assert(addressFromEcdsaStar == sigInputData.address);

        let address_dec: bigint = BigInt(addressFromEcdsa);

        let balance;
        if (sigInputData.balance.slice(-1) == 'n') {
            balance = BigInt(sigInputData.balance.substring(0, sigInputData.balance.length - 1));
        } else {
            balance = BigInt(sigInputData.balance);
        }

        return {
            signature: ecdsaStarSig,
            accountData: {
                address: address_dec,
                balance,
            }
        };
    });

    let outputData: ProofOfAssetsInputFileShape = {
        accountAttestations
    }

    const json = JSON.stringify(outputData, jsonReplacer, 2);
    fs.writeFileSync(outputPath, json);
});
