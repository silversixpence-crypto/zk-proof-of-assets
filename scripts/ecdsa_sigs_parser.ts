// https://docs.ethers.org/v6/api/crypto/#SigningKey_recoverPublicKey

import * as ethers from "ethers";
import { AccountAttestation, EcdsaSignature, EcdsaStarSignature, ProofOfAssetsInputFileShape } from "./lib/interfaces";
import { jsonReplacer } from "../scripts/lib/json_serde";
import { ecdsa_star_from_ecdsa } from "./lib/ecdsa_star";

const fs = require('fs');
const assert = require('assert');

interface SignatureData {
    address: string,
    balance: bigint,
    signature: EcdsaSignature,
}

var argv = require('minimist')(process.argv.slice(2), {
    alias: {
        signaturesPath: ['signatures', 's'],
        outputDir: ['output-dir', 'o'],
    },
});

let signaturesPath = argv.signaturesPath;
let outputDir = argv.outputDir;

fs.readFile(signaturesPath, function read(err: any, jsonIn: any) {
    if (err) {
        throw err;
    }

    let sigsInputData: SignatureData[] = JSON.parse(jsonIn);
    let num_sigs = sigsInputData.length;

    let accountData: AccountAttestation[] = sigsInputData.map(sigInputData => {
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

        return {
            signature: ecdsaStarSig,
            account_data: {
                address: address_dec,
                balance: sigInputData.balance,
            }
        };
    });

    let outputData: ProofOfAssetsInputFileShape = {
        account_data: accountData,
    }

    const json = JSON.stringify(outputData, jsonReplacer, 2);
    let filename = "input_data_for_" + num_sigs + "_accounts.json";
    let outputPath = path.join(outputDir, filename);
    fs.writeFileSync(outputPath, json);
});
