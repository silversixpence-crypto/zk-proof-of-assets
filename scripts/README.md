# Summary of scripts in this directory

Note that the only one needed to 

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
```javascript
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
            // ...
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

FLAGS:

    -b               Big circuits. Perform optimizations for large circuits:
                     - Use C++ circom witness generation (default is wasm)
                     - Use patched version of node (path to this must be set with '-n'), see these for more info
                       https://hackmd.io/V-7Aal05Tiy-ozmzTGBYPA#Install-patched-node
                       https://github.com/hermeznetwork/phase2ceremony_4/blob/main/VERIFY.md#adding-swap-and-tweeking-the-os-to-accept-high-amount-of-memory
                     - Use rapidsnark (path to this must be set with '-r'), see this for more info
                       https://hackmd.io/V-7Aal05Tiy-ozmzTGBYPA#Install-rapidsnark-from-source

    -q               Quick commands only
                     This skips proof generation, which is useful if you only want to do witness generation

    -v               Print commands that are run (set -x)

    -h               Help

OPTIONS:

    -B <PATH>        Build directory, where all the build artifacts are placed
                     Default is '<repo_root_dir>/build'

    -n <PATH>        Path to the patched node binary (needed for '-b')
                     Can also be set with the env var PATCHED_NODE_PATH

    -p <DIR>         Proof directory, where the witness & g16 proof will be written to
                     Default is the same as the build directory

    -r <PATH>        Path to the rapidsnark binary (needed for big circuits, see '-b')
                     Can also be set with the env var RAPIDSNARK_PATH

    -Z <PATH>        Path to proving key (zkey)
                     Default is '<build_dir>/<circuit_name>_final.zkey'

ARGS:

    <circuit_path>   Path to a the circom circuit to generate a witness for

    <signals_path>   Path to the json file containing the input signals for the circuit
```

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

FLAGS:

    -b               Big circuits. Perform optimizations for large circuits:
                     - Use C++ circom witness generation (default is wasm)
                     - Do not let circom try to optimize linear constraints (--02) which takes significantly longer on large circuits
                     - Use patched version of node (path to this must be set with '-n'), see these for more info
                       https://hackmd.io/V-7Aal05Tiy-ozmzTGBYPA#Install-patched-node
                       https://github.com/hermeznetwork/phase2ceremony_4/blob/main/VERIFY.md#adding-swap-and-tweeking-the-os-to-accept-high-amount-of-memory

    -q               Quick commands only. This skips proving & verification key generation.
                     Useful for testing when you only want to do compilation & witness generation.

    -r               Apply random beacon to get the final proving key (zkey)

    -v               Print commands that are run (set -x)

    -h               Help

OPTIONS:

    -B <PATH>        Build directory, where all the build artifacts are placed
                     Default is '<repo_root_dir>/build'

    -n <PATH>        Path to the patched node binary (needed for '-b')
                     Can also be set with the env var PATCHED_NODE_PATH

    -t <PATH>        Powers of tau (ptau) file path
                     Can be downloaded from here: https://github.com/iden3/snarkjs#7-prepare-phase-2
                     This is required unless you provide a pre-generated zkey (see '-Z')
                     If '-t' & '-Z' are set then '-Z' is preferred

    -Z <PATH>        Path to an already-generated proving key (zkey)
                     This will skip the lengthy zkey generation

ARGS:

    <circuit_path>   Path to a the circom circuit to be compiled & have key generation done for
```

## [G16 Verify](./g16_verify.sh)

Groth16 proof verification for circom circuits.

```bash
USAGE:
    ./g16_verify.sh [FLAGS] [OPTIONS] <circuit_path>

DESCRIPTION:
    This script does the following:
    1. Verify the Groth16 proof in <proof_dir>, which is assumed to be a proof for <circuit_path>

FLAGS:

    -b               Big circuits. Perform optimizations for large circuits:
                     - Use patched version of node (path to this must be set with '-n'), see these for more info
                       https://hackmd.io/V-7Aal05Tiy-ozmzTGBYPA#Install-patched-node
                       https://github.com/hermeznetwork/phase2ceremony_4/blob/main/VERIFY.md#adding-swap-and-tweeking-the-os-to-accept-high-amount-of-memory

    -w               Verify the witness

    -z               Verify the final proving key (zkey)
                     You must also specify the ptau file path with '-t'
                     WARN: this takes long for large circuits

    -v               Print commands that are run (set -x)

    -h               Help

OPTIONS:

    -B <PATH>        Build directory, where all the build artifacts are placed
                     Default is '<repo_root_dir>/build'

    -n <PATH>        Path to the patched node binary (needed for '-b')
                     Can also be set with the env var PATCHED_NODE_PATH

    -p <DIR>         Proof directory, where the witness & g16 proof will be written to
                     Default is the same as the build directory

    -t <PATH>        Powers of tau (ptau) file path (used for verifying the zkey, see '-z')

    -Z <PATH>        Path to proving key (zkey)
                     Default is '<build_dir>/<circuit_name>_final.zkey'

ARGS:

    <circuit_path>   Path to a the circom circuit to generate a witness for
```

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

```bash
Setup various software required to used the zk-proof-of-asset repo.

USAGE:
    ./machine_initialization.sh [FLAGS] [OPTIONS]

DESCRIPTION:
    This script does the following:
    1. Installs a bunch of software using the APT package manager
    2. Installs Rust via their install script
    3. Clones the Circom repo, and builds from source
    4. Clones the pyenv repo, and installs Python 3.10 & 3.6
    5. Clones the node repo, selects a particular commit, and builds from source
    6. Installs nvm via their install script, and installs latest npm
    7. Clones rapidsnark repo, and builds from source
    8. Installs pnpm via their install script
    9. Print out the `export` command that needs to be run manually

TROUBLESHOOTING:

    If the npm install fails with this error:
      > Installing latest LTS version.
      > Downloading and installing node v20.11.0...
      > Binary download failed, trying source.
    Then run this command manually:
      `export NVM_DIR=\"$HOME/.nvm\" && [ -s \"$NVM_DIR/nvm.sh\" ] && \. \"$NVM_DIR/nvm.sh\" && nvm install --lts`.

    If the pnpm install fails with this error:
      > ==> Downloading pnpm binaries 8.15.1
      > WARN using --force I sure hope you know what you are doing
      > Copying pnpm CLI from /tmp/tmp.a13YBtCUZy/pnpm to /root/.local/share/pnpm/pnpm
      > ERR_PNPM_UNKNOWN_SHELL Could not infer shell type.
    Then run this command manually (with different tmp file):
      `SHELL=\"$SHELL\"  /tmp/tmp.PZoYjFP8NI/pnpm setup --force`

FLAGS:

     -c            AWS CloudWatch memory metrics
                   See this for more info https://stackoverflow.com/questions/42317062/how-to-monitor-ec2-instances-by-memory

     -P            Download ptau file number $DEFAULT_PTAU_SIZE & put in $HOME/zk-proof-of-assets

     -S            Create a swap file with default size: $DEFAULT_SWAP_SIZE

     -v            Print commands that are run (set -x)

     -h            Help

OPTIONS:

     -b <BRANCH>   Checkout <BRANCH> in $HOME/zk-proof-of-assets

     -p <NUM>      Download ptau file <NUM> & put in $HOME/zk-proof-of-assets
                   See all ptau files here https://github.com/iden3/snarkjs?tab=readme-ov-file#7-prepare-phase-2

     -r <DIR>      Clone zk-proof-of-assets repo into <DIR>
                   Also install dependencies and apply patches to dependencies

     -s <SIZE>     Create swap file of size <SIZE> (recommended for large circuits)
```

## Merkle tree generator ([Rust](./merkle_tree.rs) & [TypeScript](./merkle_tree.ts) versions)

```bash
Construct a Merkle Tree for the anonymity set of Ethereum addresses & balances

Usage: merkle-tree --anon-set <FILE_PATH> --poa-input-data <FILE_PATH> --output-dir <DIR_PATH>

Options:
  -a, --anon-set <FILE_PATH>        Path to the csv anonymity set file, with headings "address,eth_balance"
  -p, --poa-input-data <FILE_PATH>  Path to the PoA input data file (output from ecdsa_sigs_parser.ts script)
  -o, --output-dir <DIR_PATH>       Directory where the proofs & root hash files will be written to
  -h, --help                        Print help
```

This is the output of the `-h` option for CLI of the Rust version. The Rust one is faster than the TS one, and the TS one is just kept around for checking correctness of the computation.

Ideally we need the Merkle Tree build to be
parallelized because the Rust script takes 2.5 hrs to generate a tree for
a set of size 10M. The hash function used for the Merlke Tree is Poseidon.

## [Pedersen commitment checker](./pedersen_commitment_checker.ts)

Verify that the Pedersen commitment calculated from the secret values
matches the one that was outputted by the layer 3 circuit.

```bash
npx ts-node ./scripts/pedersen_commitment_checker.ts \
              --layer-three-public-inputs <json_with_public_inputs_for_layer_3_circuit> \
              --blinding-factor <blinding_factor>
```

## [Sanitize G16 proof](./sanitize_groth16_proof.py)

This script takes the proof files generated by Rapidsnark/Snarkjs, and converts them to input files for another circuit. The code was copied from [the circom-pairing library](https://github.com/yi-sun/circom-pairing/blob/107c316223a08ac577522c54edd81f0fc4c03130/python/bn254.ipynb)
