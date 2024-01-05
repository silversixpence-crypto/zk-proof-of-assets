function bitsToBytes(a) {
  const b = []

  for (let i = 0; i < a.length; i++) {
    const p = Math.floor(i / 8)
    if (b[p] == undefined) {
      b[p] = 0
    }
    if (a[i] == 1) {
      b[p] |= 1 << i % 8
    }
  }
  return b
}

function bytesToBits(b) {
  const bits = []
  for (let i = 0; i < b.length; i++) {
    for (let j = 0; j < 8; j++) {
      if ((Number(b[i]) & (1 << j)) > 0) {
        // bits.push(Fr.e(1));
        bits.push(1)
      } else {
        // bits.push(Fr.e(0));
        bits.push(0)
      }
    }
  }
  return bits
}

function hexToBytes(hex) {
  for (var bytes = [], c = 0; c < hex.length; c += 2)
    bytes.push(parseInt(hex.substr(c, 2), 16))
  return bytes
}

function bytesToHex(bytes) {
  for (var hex = [], i = 0; i < bytes.length; i++) {
    var current = bytes[i] < 0 ? bytes[i] + 256 : bytes[i]
    hex.push((current >>> 4).toString(16))
    hex.push((current & 0xf).toString(16))
  }
  return hex.join('')
}

// same example as here: https://github.com/vocdoni/keccak256-circom/blob/master/test/keccak.js#L123
// 32 bits
const inputHex = "74657374"

// https://emn178.github.io/online-tools/keccak_256.html
// 256 bits
const outputHex = "9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658"

console.log(bytesToBits(hexToBytes(inputHex)).toString())
console.log(bytesToBits(hexToBytes(outputHex)).toString())
