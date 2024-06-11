# Summary of scripts in this directory

Note that the only script in this directory that needs to be used by the prover/custodian is [full_workflow.sh](./full_workflow.sh), the rest of the scripts are all used by this main workflow and so do not need to be invoked directly. But descriptions of them are given below, anyway.

## [Full workflow](./full_workflow.sh)

```bash
"
Proof of Assets ZK proof workflow.

USAGE:
    ./full_workflow.sh [FLAGS] [OPTIONS] <signatures_path> <anonymity_set_path> <blinding_factor>

DESCRIPTION:
    Note that only the Ethereum blockchain is currently supported.

    This script does the following:
    1. Converts the given ECDSA signatures to ECDSA* signatures, which are required for the circuits
    2. Generates the final Circom circuits based on the pre-written templates & the provided inputs
    3. Generate a Merkle Tree for the anonymity set
    4. Invoke g16_setup.sh for the 3 layers to generate the proving keys (zkeys) (done in parallel by default)
    5. Save the zkeys in the zkey directory, for reuse in future runs
    6. Invoke g16_prove.sh for all batches of layers 1 & 2, in parallel
    7. Invoke g16_prove.sh for final layer 3 circuit

FLAGS:

    -s                      Run the circuit setup script (g16_setup.sh) sequentially for all layers
                            The default is to run the setup for each layer in parallel,
                              but it can be very resource-hungry (depending on number of signatures)
                              and if the machine does not have the resources then running
                              in parallel will be slower than running sequentially.

    -v                      Print commands that are run (set -x)

    -h                      Help (print this text)

OPTIONS:

    -b <NUM>                Ideal batch size (this may not be the resulting batch size)
                            Default is `ceil(num_sigs / 5)`

    -B <PATH>               Build directory, where all the build artifacts are placed
                            Default is '<repo_root_dir>/build'

ARGS:

    <signatures_path>       Path to the json file containing the ECDSA signatures of the owned accounts
                            The json file should be a list of entries of the form:
                            {
                              "address": "0x72d0de0955fdba5f62af04b6d1029e4a5fdba5f6",
                              "balance": "5940527217576722726n",
                              "signature": {
                                "v": 28,
                                "r": "0x4b192b5b734f7793e28313a9f269f1f3ad1e0587a395640f8f994abdb5d750a2",
                                "s": "0xdba067cd36db3a3603649fdbb397d466021e6ef0307a41478b9aaeb47d0df6a5",
                                "msghash": "0x5f8465236e0a23dff20d042e450704e452513ec41047dd0749777b1ff0717acc"
                              }
                            }


    <anonymity_set_path>    Path to the CSV file containing the anonymity set of addresses & balances
                            Headings should be \"address,eth_balance\"

    <blinding_factor>       Blinding factor for the Pedersen commitment
                            The Pedersen commitments are done on the 25519 elliptic curve group
                            Must be a decimal value less than `2^255 - 19`
"
```

---

*The helper scripts..*

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

Ethereum ECDSA to ECDSA* coverter.

This script takes a list of type `SignatureData` and converts it to a list of type
`AccountAttestation`. A check is done to make sure the pubkey recovered from the
signature matches the provided Ethereum address.

Using this to recover the pubkey from the sig:
https://docs.ethers.org/v6/api/crypto/#SigningKey_recoverPublicKey

<details>

<summary>Input & output json shapes of the script</summary>

ecdsa_sigs_parser.ts converts multiple ecdsa signatures of the form:
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
and turns it into an ecdsa* signature (extra `r_prime` term) of the form:
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
</details>

A check is done to make sure the pubkey recovered from the
signature matches the provided Ethereum address.

### Usage

There is a basic CLI that can be invoked like so:
```bash
npx ts-node ./scripts/ecdsa_sigs_parser.ts \
              --signatures <path_to_input_ecdsa_sigs_json> \
              --output-path <path_for_output_ecdsa_star_sigs_json>
```

## [G16 Prove](./g16_prove.sh)

Groth16 proof generation for circom circuits.

```bash
"
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
"
```

## [G16 Setup](./g16_setup.sh)

Groth16 setup for circom circuits.

```bash
"
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
"
```

## [G16 Verify](./g16_verify.sh)

Groth16 proof verification for circom circuits.

```bash
"
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
"
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

*Some of this code was taken from the [batch-ecdsa library](https://github.com/puma314/batch-ecdsa/blob/b512c651f497985a74858154e4a69bcdaf02443e/test/utils.ts)*

Format data for use in layer 1 circuit.

This script takes the output of ecdsa_sigs_parser.ts and converts it to the format required by the layer 1 circuit.

Note that the output of ecdsa_sigs_parser.ts contains all the signatures, but
we only want to take a portion of them for each batch. We can choose which
portion via the index options in the CLI.

<details>

<summary>The output file has the following shape</summary>

```javascript
{
  "r": [
    [
      "8283825256485755217",
      // ...
    ],
    // ...
  ],
  "s": [
    [
      "7057909857611246358",
      // ...
    ],
    // ...
  ],
  "rprime": [
    [
      "17472741145835596079",
      // ...
    ],
    // ...
  ],
  "pubkey": [
    [
      [
        "17105043016749647727",
        // ...
      ],
      // ...
    ],
    // ...
  ],
  "msghash": [
    [
      "4259029091327649082",
      // ...
    ],
    // ...
  ]
}
```
</details>

Script can be invoked like so:

```bash
npx ts-node ./scripts/input_prep_for_layer_one.ts \
            --poa-input-data <path_to_output_of_ecdsa_sigs_parser_script> \
            --write-layer-one-data-to <dir> \
            --account-start-index <index> \
            --account-end-index <index>
```

## [Input prep - layer 2](./input_prep_for_layer_two.ts)

Format data for use in layer 2 circuit.

This script takes
1. the output of ecdsa_sigs_parser.ts: `ProofOfAssetsInputFileShape`
2. merkle root (`bigint`) & proofs (`Proofs`) from merkle_tree.rs
3. layer 1 proof (after sanitization with sanitize_groth16_proof.py): `Groth16ProofAsInput`
and converts it to the format required by the layer 2 circuit: `LayerTwoInputFileShape`

Note that the output of ecdsa_sigs_parser.ts contains all the signatures, but
we only want to take a portion of them for each batch. We can choose which
portion via the index options in the CLI.

<details>

<summary>The output file has the following shape</summary>

```javascript
{
  "gamma2": [
    [
      [
        5896345417453,
        // ...
      ],
      // ...
    ],
    // ...
  ],
  "delta2": [
    [
      [
        3655126963217,
        // ...
      ],
      // ...
    ],
    // ...
  ],
  "negalfa1xbeta2": [
    [
      [
        4063420080633,
        // ...
      ],
      // ...
    ],
    // ...
  ],
  "IC": [
    [
      [
        3438634672293,
        // ...
      ],
      // ...
    ],
    // ...
  ],
  "negpa": [
    [
      6443468478906,
      // ...
    ],
    // ...
  ],
  "pb": [
    [
      [
        565327091242,
        // ...
      ],
      // ...
    ],
    // ...
  ],
  "pc": [
    [
      1100766861909,
      // ...
    ],
    // ...
  ],
  "pubkey_x_coord_hash": "9000...",
  "pubkey": [
    [
      [
        "17105043016749647727",
        // ...
      ],
      // ...
    ],
    // ...
  ],
  "leaf_addresses": [
    "58549...",
    // ...
  ],
  "leaf_balances": [
    "354",
    // ...
  ],
  "merkle_root": "2138971...",
  "path_elements": [
    [
      "11684240...",
      // ...
    ],
    // ...
  ],
  "path_indices": [
    [
      0,
      // ...
    ],
    // ...
  ]
}
```
</details>

<details>

<summary>Merkle proofs & root files are created by merkle_tree.rs</summary>

Merkle root file looks like this:
```json
{
  "__bigint__": "15472712420445845353699436315172899903146950857649372579231961778780845454369"
}
```

Merkle proofs file looks like this:
```javascript
{
  "leaves": [
    {
      "address": {
        "__bigint__": "206933892483518574352511647678199729493848065659"
      },
      "balance": {
        "__bigint__": "1058748567537136135"
      },
      "hash": {
        "__bigint__": "7851871883103058869308994773056478210002897307428913610928488050559773655664"
      }
    },
    // ...
  ],
  "path_elements": [
    [
      {
        "__bigint__": "7904234440378902442369762803695352688549121058277502644031777861983205439866"
      },
      // ...
    ],
    // ...
  ],
  "path_indices": [
    [
      0,
      // ...
    ],
    // ...
  ]
}
```
</details>

```bash
npx ts-node ./scripts/input_prep_for_layer_two.ts \
            --poa-input-data <path_to_output_of_ecdsa_sigs_parser_script> \
            --merkle-root <path_to_merkle_root_json> \
            --merkle-proofs <path_to_merkle_proofs_json> \
            --layer-one-sanitized-proof <output_of_sanitize_groth16_proof_script> \
            --write-layer-two-data-to <path_to_output_json> \
            --account-start-index <index> \
            --account-end-index <index>
```

## [Input prep - layer 3](./input_prep_for_layer_three.ts)

Format data for use in layer 3 circuit.

This script takes
1. merkle root: `bigint`
2. layer 2 proof (after sanitization with sanitize_groth16_proof.py): `Groth16ProofAsInput`
3. blinding factor for the final Pedersen commitment of asset balance sum
and converts it to the format required by the layer 3 circuit: `LayerThreeInputFileShape`
<details>

<summary>The output file has the following shape</summary>

```javascript
{
  "gamma2": [
    [
      [
        [
          5896345417453,
          // ...
        ],
        // ...
      ],
      // ...
    ]
  ],
  "delta2": [
    [
      [
        [
          2433806394190,
          // ...
        ],
        // ...
      ],
      // ...
    ]
  ],
  "negalfa1xbeta2": [
    [
      [
        [
          4063420080633,
          // ...
        ],
        // ...
      ],
      // ...
    ]
  ],
  "IC": [
    [
      [
        [
          6650711866057,
          // ...
        ],
        // ...
      ],
      // ...
    ]
  ],
  "negpa": [
    [
      [
        5123590522751,
        // ...
      ],
      // ...
    ]
  ],
  "pb": [
    [
      [
        [
          5750824120771,
          // ...
        ],
        // ...
      ],
      // ...
    ]
  ],
  "pc": [
    [
      [
        2843075561801,
        // ...
      ],
      // ...
    ]
  ],
  "balances": [
    632
  ],
  "merkle_root": "2138971...",
  "ped_com_generator_g": [
    [
      "6836562328990639286768922",
      // ...
    ],
    // ...
  ],
  "ped_com_generator_h": [
    [
      "25216993871230434893611732",
      // ...
    ],
    // ...
  ],
  "ped_com_blinding_factor": [
    "0",
    // ...
  ]
}
```

</details>

```bash
npx ts-node ./scripts/input_prep_for_layer_three.ts \
        --merkle-root <path_to_merkle_root_json> \
        --layer-two-sanitized-proof <output_of_sanitize_groth16_proof_script> \
        --write-layer-three-data-to <path_to_output_json> \
        --blinding-factor <num> \
        --multiple-proofs # need to set this if there is >1 batch
```

## [Machine initialization](./machine_initialization.sh)

```bash
"
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

    The script can be run multiple times without repeating work e.g. if a command
    fails then you can run the script again and it will pick up where it left off.

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
"
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

<details>

<summary>Merkle proofs & root files that are created</summary>

Merkle root file looks like this:
```json
{
  "__bigint__": "15472712420445845353699436315172899903146950857649372579231961778780845454369"
}
```

Merkle proofs file looks like this:
```javascript
{
  "leaves": [
    {
      "address": {
        "__bigint__": "206933892483518574352511647678199729493848065659"
      },
      "balance": {
        "__bigint__": "1058748567537136135"
      },
      "hash": {
        "__bigint__": "7851871883103058869308994773056478210002897307428913610928488050559773655664"
      }
    },
    // ...
  ],
  "path_elements": [
    [
      {
        "__bigint__": "7904234440378902442369762803695352688549121058277502644031777861983205439866"
      },
      // ...
    ],
    // ...
  ],
  "path_indices": [
    [
      0,
      // ...
    ],
    // ...
  ]
}
```
</details>

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

Invoke like this:
```bash
python ./scripts/sanitize_groth16_proof.py <proof_dir>
```
