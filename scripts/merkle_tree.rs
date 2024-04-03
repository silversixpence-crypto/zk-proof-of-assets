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

use std::error::Error;
use std::fs::File;
use std::path::PathBuf;

use ark_bn254::Fr;
use csv::ReaderBuilder;
use light_poseidon::{Poseidon, PoseidonBytesHasher};
use num_bigint::BigUint;
use rs_merkle::{Hasher, MerkleTree};

use clap::Parser;

use serde::Serialize;

/// Search for a pattern in a file and display the lines that contain it.
#[derive(Parser)]
struct Cli {
    /// The pattern to look for.
    pattern: String,

    /// Path to the csv anonymity set file.
    anon_set: PathBuf,

    /// Path to the PoA input data file.
    poa_input_data: PathBuf,

    /// Directory where the proofs & root hash files will be written to.
    output_dir: PathBuf,
}

#[derive(Serialize)]
struct RootHash {
    __bigint__: String,
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

fn main() -> Result<(), Box<dyn Error>> {
    println!("Initiating Merkle Tree build..");

    let args = Cli::parse();
    let anon_set_file_path = args.anon_set; // std::env::args().nth(1).expect("No csv file name given");
    let merkle_root_path = append_to_path(args.output_dir.clone(), "merkle_root.json");
    let merkle_proofs_path = append_to_path(args.output_dir, "merkle_proofs.json");

    let mut poseidon_hasher: Poseidon<Fr> = Poseidon::<Fr>::new_circom(2)?;

    println!(
        "Trying to read given file '{:?}'",
        anon_set_file_path.clone()
    );
    let file = File::open(anon_set_file_path.clone())?;
    let mut rdr = ReaderBuilder::new().from_reader(file);

    let mut leaves: Vec<[u8; 32]> = Vec::new();

    println!(
        "Converting lines in '{:?}' into leaf nodes.. (leaf node = hash(address, balance))",
        anon_set_file_path
    );

    for result in rdr.records() {
        let record = result?;
        let address = record.get(0).ok_or("Missing address")?;
        let eth_balance = record.get(1).ok_or("Missing eth_balance")?;

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

    println!("Done creating leaves");

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

    println!("Creating Merkle tree..");
    let merkle_tree = MerkleTree::<MyPoseidon>::from_leaves(&leaves);
    println!("Done creating Merkle tree");

    write_merkle_root(&merkle_tree, merkle_root_path);

    // TODO we need to
    // a) ingest the poa input data file
    // b) gen proofs and write these to the out dir

    // merkle_tree.proof(leaf_indices)

    Ok(())
}
