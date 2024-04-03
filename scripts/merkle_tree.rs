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

use csv::ReaderBuilder;
use rs_merkle::{Hasher, MerkleTree};

use std::error::Error;
use std::fs::File;

use ark_bn254::Fr;
use light_poseidon::{Poseidon, PoseidonBytesHasher};

use num_bigint::BigUint;

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

fn main() -> Result<(), Box<dyn Error>> {
    println!("Initiating Merkle Tree build..");

    let input_file_name = std::env::args().nth(1).expect("No csv file name given");

    let mut poseidon_hasher: Poseidon<Fr> = Poseidon::<Fr>::new_circom(2).unwrap();

    println!("Trying to read given file '{}'", input_file_name.clone());
    let file = File::open(input_file_name.clone())?;
    let mut rdr = ReaderBuilder::new().from_reader(file);

    let mut leaves: Vec<[u8; 32]> = Vec::new();

    println!("Converting lines in '{}' into leaf nodes.. (leaf node = hash(address, balance))", input_file_name);

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

    println!("Number of leaves (after adding padding nodes): {}", leaves.len());

    leaves.sort();

    println!("Creating Merkle tree..");
    let merkle_tree = MerkleTree::<MyPoseidon>::from_leaves(&leaves);
    println!("Done creating Merkle tree");

    let root: [u8; 32] = merkle_tree.root().unwrap();
    println!("Root hash: {:?}", BigUint::from_bytes_be(&root[..]));

    Ok(())
}
