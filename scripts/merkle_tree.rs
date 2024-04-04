//! Create a Merkle Tree from a set of Ethereum addresses & balances.
//!
//! This script is temporary. Ideally we need the Merkle Tree build to be
//! parallelized because this script takes 2.5 hrs to generate a tree for
//! a set of size 10M.
//!
//! This script does not do error handling since it is just meant to be used as
//! a simple, standalone script. This means that there are a lot of uses of
//! `unwrap()`.
//!
//! The hash function used for the Merlke Tree is Poseidon.

use std::fs::File;
use std::io::BufReader;
use std::path::PathBuf;
use std::{error::Error, str::FromStr};

use ark_bn254::Fr;
use csv::ReaderBuilder;
use light_poseidon::{Poseidon, PoseidonBytesHasher};
use num_bigint::BigUint;
use rs_merkle::{Hasher, MerkleProof, MerkleTree};

use clap::Parser;

use serde::{Deserialize, Serialize};

/// Search for a pattern in a file and display the lines that contain it.
#[derive(Parser)]
struct Cli {
    /// Path to the csv anonymity set file.
    #[arg(short, long, value_name = "FILE_PATH")]
    anon_set: PathBuf,

    /// Path to the PoA input data file.
    #[arg(short, long, value_name = "FILE_PATH")]
    poa_input_data: PathBuf,

    /// Directory where the proofs & root hash files will be written to.
    #[arg(short, long, value_name = "DIR_PATH")]
    output_dir: PathBuf,
}

#[derive(Serialize)]
struct RootHash {
    __bigint__: String,
}

#[derive(Deserialize)]
struct ProofOfAssetsInputFileShape {
    accountAttestations: Vec<AccountAttestations>,
}

#[derive(Deserialize)]
struct AccountAttestations {
    signature: Signature,
    accountData: AccountData,
}

#[derive(Deserialize)]
struct AccountData {
    address: BigIntJson,
    balance: BigIntJson,
}

#[derive(Deserialize)]
struct Signature {
    r: BigIntJson,
    s: BigIntJson,
    r_prime: BigIntJson,
    pubkey: Pubkey,
    msghash: Uint8Arr,
}

#[derive(Deserialize)]
struct Uint8Arr {
    __uint8array__: Vec<u8>,
}

#[derive(Deserialize, Serialize)]
struct BigIntJson {
    __bigint__: String,
}

#[derive(Deserialize)]
struct Pubkey {
    x: BigIntJson,
    y: BigIntJson,
}

#[derive(Serialize)]
struct Proofs {
    leaves: Vec<Leaf>,
    path_elements: Vec<Vec<BigIntJson>>,
    path_indices: Vec<Vec<u8>>,
}

#[derive(Serialize)]
struct Leaf {
    address: BigIntJson,
    balance: BigIntJson,
    hash: BigIntJson,
}

/// Copied from
/// https://users.rust-lang.org/t/how-to-get-a-substring-of-a-string/1351/11
trait StringUtils {
    fn substring(&self, start: usize, len: usize) -> &str;
}
impl StringUtils for str {
    fn substring(&self, start: usize, len: usize) -> &str {
        let mut char_pos = 0;
        let mut byte_start = 0;
        let mut it = self.chars();
        loop {
            if char_pos == start {
                break;
            }
            if let Some(c) = it.next() {
                char_pos += 1;
                byte_start += c.len_utf8();
            } else {
                break;
            }
        }
        char_pos = 0;
        let mut byte_end = byte_start;
        loop {
            if char_pos == len {
                break;
            }
            if let Some(c) = it.next() {
                char_pos += 1;
                byte_end += c.len_utf8();
            } else {
                break;
            }
        }
        &self[byte_start..byte_end]
    }
}

/// We have this empty struct because we cannot implement a foreign trait (Hasher)
/// for a foreign struct (Poseidon).
#[derive(Clone)]
struct MyPoseidon {}

impl Hasher for MyPoseidon {
    type Hash = [u8; 32];

    fn hash(data: &[u8]) -> Self::Hash {
        let mut left_node_bytes = [0u8; 32];
        let mut right_node_bytes = [0u8; 32];

        left_node_bytes.copy_from_slice(&data[..32]);
        right_node_bytes.copy_from_slice(&data[32..]);

        // left node + right node = 2 things to hash
        let mut poseidon_hasher = Poseidon::<Fr>::new_circom(2).unwrap();

        poseidon_hasher
            .hash_bytes_be(&[&left_node_bytes, &right_node_bytes])
            .unwrap()
    }

    fn concat_and_hash(left: &Self::Hash, right: Option<&Self::Hash>) -> Self::Hash {
        match right {
            Some(right_hash) => {
                let mut joined = [0u8; 64];
                let (left_slice, right_slice) = joined.split_at_mut(32);
                left_slice.copy_from_slice(left);
                right_slice.copy_from_slice(right_hash);

                Self::hash(&joined)
            }
            None => *left,
        }
    }
}

fn append_to_path(p: PathBuf, s: &str) -> PathBuf {
    let mut p = p.into_os_string();
    p.push("/");
    p.push(s);
    p.into()
}

fn write_merkle_root(merkle_tree: &MerkleTree<MyPoseidon>, root_path: PathBuf) {
    let root_bytes: [u8; 32] = merkle_tree.root().unwrap();
    let root_bigint = BigUint::from_bytes_be(&root_bytes[..]);
    let root_encoded: RootHash = RootHash {
        __bigint__: root_bigint.to_string(),
    };

    let mut root_file = File::create(root_path.clone()).expect("Merkle root file creation failed");
    let _ = serde_json::to_writer_pretty(root_file, &root_encoded);

    println!(
        "Root hash {:?} written to file {:?}",
        root_bigint, root_path
    );
}

fn build_leaves(anon_set_file_path: PathBuf) -> Vec<[u8; 32]> {
    let mut poseidon_hasher: Poseidon<Fr> =
        Poseidon::<Fr>::new_circom(2).expect("Failed to initialize Poseidon hash function");

    println!(
        "Trying to read given file '{:?}'",
        anon_set_file_path.clone()
    );
    let file = File::open(anon_set_file_path.clone()).expect("Failed to open anon set file");
    let mut rdr = ReaderBuilder::new().from_reader(file);

    let mut leaves: Vec<[u8; 32]> = Vec::new();

    println!(
        "Converting lines in '{:?}' into leaf nodes.. (leaf node = hash(address, balance))",
        anon_set_file_path
    );

    for result in rdr.records() {
        let record = result.expect("Failed to find line in csv file");

        let address = record
            .get(0)
            .ok_or("Missing address")
            .expect("Failed to find address in line in csv file");

        let eth_balance = record
            .get(1)
            .ok_or("Missing eth_balance")
            .expect("Failed to find balance in line in csv file");

        // Assumes the address is in hex format like 0x00000000219ab540356cbb839cbe05303d7705fa
        let address_bigint =
            BigUint::parse_bytes(address.substring(2, address.len()).as_bytes(), 16).unwrap();

        // Assumes the balance is in decimal format like 40574880376960633295804796
        let eth_balance_bigint = BigUint::parse_bytes(eth_balance.as_bytes(), 10).unwrap();

        let hash = poseidon_hasher
            .hash_bytes_be(&[
                &address_bigint.to_bytes_be(),
                &eth_balance_bigint.to_bytes_be(),
            ])
            .unwrap();

        leaves.push(hash);
    }

    println!("Done creating {} leaves", leaves.len());

    // Add 0-valued nodes to make the tree full
    let size = leaves.len() as f64;
    let height = size.log2().ceil() as u32;
    for _i in leaves.len()..2usize.pow(height) {
        leaves.push([0u8; 32]);
    }

    println!(
        "Number of leaves (after adding padding nodes): {}",
        leaves.len()
    );

    leaves.sort();
    leaves
}

struct OwnedLeaf {
    hash: [u8; 32],
    address: String,
    balance: String,
}

fn build_path_indices(height: usize, index: usize) -> Vec<u8> {
    let mut path_indices = Vec::new();
    let mut current_index = index;

    for _i in 0..height - 1 {
        let value = if current_index % 2 == 0 { 0 } else { 1 };
        path_indices.push(value);
        current_index = current_index / 2;
    }

    path_indices
}

fn generate_proofs(
    poa_input_path: PathBuf,
    anon_set_leaves: &Vec<[u8; 32]>,
    merkle_tree: &MerkleTree<MyPoseidon>,
    output_path: PathBuf,
) {
    let mut poseidon_hasher: Poseidon<Fr> =
        Poseidon::<Fr>::new_circom(2).expect("Failed to initialize Poseidon hash function");

    let poa_input_file = File::open(poa_input_path).expect("Failed to open PoA input data file");
    let poa_input_reader = BufReader::new(poa_input_file);
    let poa_input_data: ProofOfAssetsInputFileShape =
        serde_json::from_reader(poa_input_reader).unwrap();

    // Hash address & balance of owned addresses.
    let mut owned_leaves: Vec<OwnedLeaf> = poa_input_data
        .accountAttestations
        .into_iter()
        .map(|account| {
            let address = account.accountData.address.__bigint__;
            let balance = account.accountData.balance.__bigint__;

            let address_bigint = BigUint::from_str(&address).unwrap();

            let eth_balance_bigint = BigUint::from_str(&balance).unwrap();

            let hash = poseidon_hasher
                .hash_bytes_be(&[
                    &address_bigint.to_bytes_be(),
                    &eth_balance_bigint.to_bytes_be(),
                ])
                .unwrap();

            OwnedLeaf {
                hash,
                address,
                balance,
            }
        })
        .collect();

    owned_leaves.sort_by(|a, b| a.hash.cmp(&b.hash));

    let mut owned_leaf_indices = Vec::<usize>::new();
    let mut anon_i = 0;

    // Search anon set for owned addresses, panic if not found.
    for owned_i in 0..owned_leaves.len() {
        let target = owned_leaves.get(owned_i).unwrap().hash;

        while *anon_set_leaves.get(anon_i).unwrap() != target {
            if anon_i == anon_set_leaves.len() - 1 {
                panic!(
                    "Owned leaf {} at index {} does not exist in the anonymity set",
                    owned_leaves.get(owned_i).unwrap().address,
                    owned_i
                );
            }
            anon_i += 1;
        }

        owned_leaf_indices.push(anon_i);
    }

    let mut output_leaves: Vec<Leaf> = Vec::new();
    let mut output_path_elements: Vec<Vec<BigIntJson>> = Vec::new();
    let mut output_path_indices: Vec<Vec<u8>> = Vec::new();

    // Generate Merkle proofs & construct json output.
    for i in 0..owned_leaf_indices.len() {
        let anon_set_index = *owned_leaf_indices.get(i).unwrap();

        let proof: MerkleProof<MyPoseidon> = merkle_tree.proof(&[anon_set_index]);

        output_leaves.push(Leaf {
            address: BigIntJson {
                __bigint__: owned_leaves.get(i).unwrap().address.clone(),
            },
            balance: BigIntJson {
                __bigint__: owned_leaves.get(i).unwrap().balance.clone(),
            },
            hash: BigIntJson {
                __bigint__: BigUint::from_bytes_be(&owned_leaves.get(i).unwrap().hash[..])
                    .to_string(),
            },
        });

        let path_elements: Vec<BigIntJson> = proof
            .proof_hashes()
            .to_vec()
            .into_iter()
            .map(|u8_arr: [u8; 32]| BigIntJson {
                __bigint__: BigUint::from_bytes_be(&u8_arr[..]).to_string(),
            })
            .collect();
        output_path_elements.push(path_elements);

        output_path_indices.push(build_path_indices(merkle_tree.depth(), anon_set_index));
    }

    let proofs = Proofs {
        leaves: output_leaves,
        path_elements: output_path_elements,
        path_indices: output_path_indices,
    };

    let file = File::create(output_path).expect("Merkle proofs file creation failed");
    let _ = serde_json::to_writer_pretty(file, &proofs);
}

fn main() -> Result<(), Box<dyn Error>> {
    println!("Initiating Merkle Tree build..");

    let args = Cli::parse();
    let anon_set_file_path = args.anon_set;
    let poa_input_path = args.poa_input_data;
    let merkle_root_path = append_to_path(args.output_dir.clone(), "merkle_root.json");
    let merkle_proofs_path = append_to_path(args.output_dir, "merkle_proofs.json");

    let leaves = build_leaves(anon_set_file_path);

    println!("Creating Merkle tree..");
    let merkle_tree = MerkleTree::<MyPoseidon>::from_leaves(&leaves);
    println!(
        "Done creating Merkle tree of height {}",
        merkle_tree.depth()
    );

    write_merkle_root(&merkle_tree, merkle_root_path);
    generate_proofs(poa_input_path, &leaves, &merkle_tree, merkle_proofs_path);

    Ok(())
}
