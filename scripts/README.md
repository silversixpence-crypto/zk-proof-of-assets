# Summary of scripts in this directory

## [Batch size optimizer](./batch_size_optimizooor.py)

Adjusts batch size to minimize the number of signatures in the final batch.

The total signatures list is split into chunks of size `batch_size`.
This is because the number of constraints for g16 circuits is limited, and the limit
is hit for a pretty small number of sigs, so we are forced to cut the list into
chunks and feed them to different snarks. Dividing the number of sigs by
`batch_size` will possibly leave a non-zero remainder.

If we want to support any amount of signatures & batch size then the last batch
could have any number of signatures in the range [0, batch_size].
Generating zkeys is expensive so we want to minimize this number to make the
zkey generation as small as possible.

See full equation & calculation here: https://www.desmos.com/calculator/vhryppb3m2

This script can be executed through CLI:
```bash
python ./scripts/batch_size_optimizooor.py <num_sigs> <ideal_num_sigs_per_batch>
```

## [ECDSA signature parser](./ecdsa_signature_parser.ts)

ecdsa_sigs_parser.ts converts multiple ecdsa signatures of the form
```json
{
  "address": "0x3e....",
  "balance": "1250...",
  "signature": {
    "v": 28,
    "r": "0x21...",
    "s": "0xfa...",
    "msghash": "0xd7..."
  }
}
```
and turns it into an ecdsa* signature (extra `r_prime` term) in a format that the circuits can ingest:
```json
{
      "signature": {
        "r": {
          "__bigint__": "868..."
        },
        "s": {
          "__bigint__": "571..."
        },
        "r_prime": {
          "__bigint__": "108..."
        },
        "pubkey": {
          "x": {
            "__bigint__": "990..."
          },
          "y": {
            "__bigint__": "792..."
          }
        },
        "msghash": {
          "__uint8array__": [
            28,
            138,
            ...
          ]
        }
      },
      "accountData": {
        "address": {
          "__bigint__": "376..."
        },
        "balance": {
          "__bigint__": "214..."
        }
      }
    }
```
A check is done to make sure the pubkey recovered from the
signature matches the provided Ethereum address.

### Usage

There is a basic CLI that can be invoked like so:
```bash
npx ts-node ./scripts/ecdsa_sigs_parser.ts \
              --signatures <path_to_input_ecdsa_sigs_json> \
              --output-path <path_for_output_ecdsa_star_sigs_json>
```

## [Full workflow](./full_workflow.sh)

TODO

## [G16 Prove](./g16_prove.sh)

Groth16 proof generation for circom circuits.

```bash
USAGE:
    ./g16_prove.sh [FLAGS] [OPTIONS] <circuit_path> <signals_path>

DESCRIPTION:
    It is assumed that the following are present in the build directory:
    - The circom witness generation files
    - The proving key (.zkey)

    This script does the following:
    1. Generate witness for <circuit_path> & <signals_path>
    2. Generate the groth16 proof for witness
```

See `./g16_prove.sh -h` for more info.

## [G16 Setup](./g16_setup.sh)

Groth16 setup for circom circuits.

```bash
USAGE:
    ./g16_setup.sh [FLAGS] [OPTIONS] <circuit_path>

DESCRIPTION:
    This script does the following:
    1. Compile the circom circuit at <circuit_path>
    2. Generate the groth16 proving key (.zkey) for the circuit (this will take long for large circuits)
    3. Generate the groth16 verification key (.vkey) for the circuit
```

See `./g16_setup.sh -h` for more info.

## [G16 Verify](./g16_verify.sh)

Groth16 proof verification for circom circuits.

```bash
USAGE:
    ./g16_verify.sh [FLAGS] [OPTIONS] <circuit_path>

DESCRIPTION:
    This script does the following:
    1. Verify the Groth16 proof in <proof_dir>, which is assumed to be a proof for <circuit_path>
```

See `./g16_verify.sh -h` for more info.

## [Generate circuits](./generate_circuits.ts)

Generates Circom code for the given input values (number of signatures, etc). It basically configures the input params for the [3 circuit layers](../circuits/).

Use CLI like this:
```bash
npx ts-node ./scripts/generate_circuits.ts --num-sigs <num_sigs_per_batch> \
                                           --num-sigs-remainder <num_sigs_in_remainder_batch> \
                                           --tree-height <merkle_tree_height> \
                                           --parallelism <num_batches> \
                                           --write-circuits-to <generated_circuits_dir> \
                                           --circuits-library-relative-path <path_to_circuits_dir_from_generated_circuits_dir>
```

## [Input prep - layer 1](./input_prep_for_layer_one.ts)

TODO 

## [Input prep - layer 2](./input_prep_for_layer_two.ts)

TODO

## [Input prep - layer 3](./input_prep_for_layer_three.ts)

TODO

## [Machine initialization](./machine_initialization.sh)

TODO

## Merkle tree generator ([Rust](./merkle_tree.rs) & [TypeScript](./merkle_tree.ts) versions)

Creates a Merkle Tree from a set of Ethereum addresses & balances. The Rust one is faster than the TS one.

These scripts are both temporary. Ideally we need the Merkle Tree build to be
parallelized because the Rust script takes 2.5 hrs to generate a tree for
a set of size 10M.

The hash function used for the Merlke Tree is Poseidon.

Use the CLI like this:
```bash
cargo run --bin merkle-tree -- \
          --anon-set <anonymity_set_path> \
          --poa-input-data <ecdsa_star_sigs_path> \
          --output-dir <dir_for_tree>
```

## [Pedersen commitment checker](./pedersen_commitment_checker.ts)

Verify that the Pedersen commitment calculated from the secret values
matches the one that was outputted by the layer 3 circuit.

```bash
npx ts-node ./scripts/pedersen_commitment_checker.ts \
              --layer-three-public-inputs <json_with_public_inputs_for_layer_3_circuit> \
              --blinding-factor <blinding_factor>
```

## [Sanitize G16 proof](./sanitize_groth16_proof.py)

TODO
