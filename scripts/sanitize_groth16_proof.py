# Some code taken from
# https://github.com/yi-sun/circom-pairing/blob/107c316223a08ac577522c54edd81f0fc4c03130/python/bn254.ipynb

from py_ecc.fields import (
    bn128_FQ as FQ,
    bn128_FQ2 as FQ2,
)
from lib.field_helper import (
    numberToArray,
    Fp12convert,
)
from py_ecc.fields import (
    bn128_FQ as FQ,
    bn128_FQ2 as FQ2,
)
from py_ecc.bn128 import (
    bn128_pairing as pairing
)
from pathlib import Path
import click
import json
import os


def Fpconvert(X, n, k):
    return numberToArray(X.n, n, k)

def Fp2convert(X, n, k):
    return [ numberToArray(X.coeffs[0].n, n, k) , numberToArray(X.coeffs[1].n, n, k) ]

def Fp12convert(X, n, k):
    basis1 = X.coeffs
    ret = []
    for i in range(6):
        fq2elt = FQ2([basis1[i].n, 0]) + FQ2([basis1[i+6].n, 0]) * FQ2([9,1])
        ret.append(Fp2convert(fq2elt, n, k))
    return ret

def convert_vkey(n, k, vkeyFile):
    with open(vkeyFile, 'r') as vkey_file:
        vkey_data = vkey_file.read()
        vkey = json.loads(vkey_data)

    x, y, z = tuple([FQ((int(x))) for x in vkey["vk_alpha_1"]])
    negalpha = ( x / z, -(y / z) )

    x, y, z = tuple([ FQ2([int(x[0]), int(x[1])]) for x in vkey["vk_beta_2"]])
    beta = ( x / z, y / z )

    x, y, z = tuple([ FQ2([int(x[0]), int(x[1])]) for x in vkey["vk_gamma_2"]])
    gamma = ( x / z, y / z )

    x, y, z = tuple([ FQ2([int(x[0]), int(x[1])]) for x in vkey["vk_delta_2"]])
    delta = ( x / z, y / z )

    public_input_count = vkey["nPublic"]

    ICs = []
    for i in range(public_input_count + 1):
        x, y, z = tuple([ FQ(int(x)) for x in vkey["IC"][i]])
        ICs.append( ( x / z, y / z ) )

    negalphabeta = pairing.pairing( beta, negalpha )

    inputParameters = {
        "gamma2": [ Fp2convert(gamma[0], n, k), Fp2convert(gamma[1], n, k)],
        "delta2": [ Fp2convert(delta[0], n, k), Fp2convert(delta[1], n, k)],
        "negalfa1xbeta2": Fp12convert(negalphabeta, n, k),
        "IC": [[Fpconvert(IC[0], n, k), Fpconvert(IC[1], n, k)] for IC in ICs],
       }

    return inputParameters


def convert_proof(n, k, proofFile):
    with open(proofFile, 'r') as proof_file:
        proof_data = proof_file.read()
    proof = json.loads(proof_data)

    x, y, z = tuple([FQ((int(x))) for x in proof["pi_a"]])
    negpi_a = (x / z, - (y / z))

    x, y, z = tuple([ FQ2([int(x[0]), int(x[1])]) for x in proof["pi_b"]])
    pi_b = (x / z, y / z)

    x, y, z = tuple([FQ((int(x))) for x in proof["pi_c"]])
    pi_c = (x / z, y / z)

    proofParameters = {
        "negpa": [Fpconvert(negpi_a[0], n, k), Fpconvert(negpi_a[1], n, k)],
        "pb": [ Fp2convert(pi_b[0], n, k), Fp2convert(pi_b[1], n, k)],
        "pc": [Fpconvert(pi_c[0], n, k), Fpconvert(pi_c[1], n, k)],
       }

    return proofParameters


def convert_public_params(n, k, publicFile):
    with open(publicFile, 'r') as public_file:
        public_data = public_file.read()
    pubInputs = json.loads(public_data)

    pubParameters  = {
        "pubInput": [],
       }
    for pubInput in pubInputs:
        pubParameters["pubInput"].append(int(pubInput))

    return pubParameters


def convert_proof_files_to_circom_input(proofFile, vkeyFile, publicFile, outputFile):
    n = 43
    k = 6

    inputParameters = convert_vkey(n, k, vkeyFile)
    proofParameters = convert_proof(n, k, proofFile)
    pubParameters = convert_public_params(n, k, publicFile)

    fullCircomInput = {**inputParameters, **proofParameters, **pubParameters}

    with open(outputFile, 'w') as outfile:
        json.dump(fullCircomInput, outfile)


@click.command()
@click.argument(
    "proofdir",
    required=1,
    type=click.Path(
        exists=True,
        file_okay=False,
        readable=True,
        path_type=Path,
    ),
)
def cli(proofdir):
    proofFile = Path(proofdir, 'proof.json')
    publicFile = Path(proofdir, 'public.json')
    outputFile = Path(proofdir, 'sanitized_proof.json')

    # TODO this whole mechanism for finding vkeys is a bit wonky.
    # We should at least log out what the program is doing.
    vkeyFile = None

    for file in os.listdir(proofdir):
        if file.endswith("_vkey.json"):
            vkeyFile = Path(proofdir, file)

    if not vkeyFile:
        parentdir = Path(proofdir, '..')
        for file in os.listdir(parentdir):
            if file.endswith("_vkey.json"):
                vkeyFile = Path(parentdir, file)

    if not vkeyFile:
        raise Exception("Cannot find vkey file")

    convert_proof_files_to_circom_input(proofFile, vkeyFile, publicFile, outputFile)

if __name__ == "__main__":
    cli()
