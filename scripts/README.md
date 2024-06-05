# Summary of scripts in this directory

## Batch size optimizer (TODO link)

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


## [ECDSA signature parser](./scripts/ecdsa_signature_parser.ts)

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
npx ts-node ./scripts/ecdsa_sigs_parser.ts --signatures <path_to_input_ecdsa_sigs_json> --output-path <path_for_output_ecdsa_star_sigs_json>
```
