// from https://github.com/0xPARC/cabal/blob/main/circuits/test/merkle.mjs

import {
  buildPoseidon
} from "circomlibjs";

import FileSystem from "fs";

const poseidon = await buildPoseidon();
const F = poseidon.F; // poseidon finite field

// NOTE: picked this as the null field element arbitrarily
const NULL_NODE = 1n;

async function buildTree(leaves, depth = 10, nullNode = NULL_NODE) {
  // pad with nullNode to guarantee a tree of the desired depth
  const requiredLeaves = 2 ** depth;
  if (leaves.length < requiredLeaves) {
    leaves = leaves.concat(Array(requiredLeaves - leaves.length).fill(nullNode));
  }

  leaves = leaves.map(BigInt);
  leaves.sort();

  // the equivalent of pathElements and pathIndices in merkle.circom
  const outputLeaves = leaves.filter(w => w !== nullNode);
  let leafToPathElements = Object.fromEntries(outputLeaves.map((w) => [w, []]));
  let leafToPathIndices = Object.fromEntries(outputLeaves.map((w) => [w, []]));

  let nodeToLeaves = Object.fromEntries(leaves.map((w) => [w, [w]]));
  let curLevel = leaves;
  while (curLevel.length > 1) {
    let newLevel = [];

    for (let i = 0; i < curLevel.length; i += 2) {
      let child1 = curLevel[i];
      let child2 = i == curLevel.length - 1 ? nullNode : curLevel[i + 1];

      let child1Leaves = nodeToLeaves[child1];
      let child2Leaves = child2 == nullNode ? [] : nodeToLeaves[child2];

      for (const leaf of child1Leaves) {
        if (leaf !== nullNode) {
          leafToPathElements[leaf].push(child2);
          leafToPathIndices[leaf].push(0);
        }
      }

      for (const leaf of child2Leaves) {
        if (leaf !== nullNode) {
          leafToPathElements[leaf].push(child1);
          leafToPathIndices[leaf].push(1);
        }
      }

      let poseidonRes = poseidon([child1, child2]);
      let parent = F.toObject(poseidonRes);

      nodeToLeaves[parent] = child1Leaves.concat(child2Leaves);

      newLevel.push(parent);
    }

    curLevel = newLevel;
  }

  return {
    root: curLevel[0],
    leafToPathElements,
    leafToPathIndices,
  };
}

async function testLeaves(leaves, depth) {
  let {
    root,
    leafToPathElements,
    leafToPathIndices
  } = await buildTree(leaves, depth);

  let witness = {};
  for (const leaf of leaves) {
    witness = {
      leaf: leaf,
      root: root,
      pathElements: leafToPathElements[leaf],
      pathIndices: leafToPathIndices[leaf]
    };
  }

  FileSystem.writeFile('scripts/merkle_input_prep/inputs.json', JSON.stringify(witness, (_, v) => typeof v === 'bigint' ? v.toString() : v), (error) => {
    if (error) throw error;
  });

}

async function generateInput() {
  let leaves = [58832943290, 9432001023, 9530201010231];
  await testLeaves(leaves, 24);
}

await generateInput();