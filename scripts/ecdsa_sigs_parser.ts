/**
Ethereum ECDSA to ECDSA* coverter.

This script takes a list of type `SignatureData` and converts it to a list of type
`AccountAttestation`. A check is done to make sure the pubkey recovered from the
signature matches the provided Ethereum address.

Using this to recover the pubkey from the sig:
https://docs.ethers.org/v6/api/crypto/#SigningKey_recoverPublicKey

===================
Usage

There is a basic CLI that can be invoked like so:
```bash
npx ts-node ./scripts/ecdsa_sigs_parser.ts \
            --signatures <path_to_input_ecdsa_sigs_json> \
            --output-path <path_for_output_ecdsa_star_sigs_json>
```
**/

import * as ethers from "ethers";
import { AccountAttestation, EcdsaSignature, EcdsaStarSignature, ProofOfAssetsInputFileShape, SignatureData } from "./lib/interfaces";
import { jsonReplacer } from "../scripts/lib/json_serde";
import { ecdsaStarFromEcdsa } from "./lib/ecdsa_star";

const fs = require('fs');
const assert = require('assert');

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
        let ecdsaStarSig = ecdsaStarFromEcdsa(ecdsaSig);
        let addressFromEcdsaStar = ethers.computeAddress("0x" + ecdsaStarSig.pubkey.toHex());

        // Extra check to make sure the address of both sigs matches the input address.
        // If this is not done the circuit will detect it.
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
