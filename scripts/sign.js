const ethers = require("ethers");               // ←  ¡v5!

const { keccak256, toUtf8Bytes, concat, arrayify, joinSignature } = ethers.utils;
const Wallet = ethers.Wallet;

if (process.argv.length !== 5) {
  console.error("Uso: node sign.js <BACKEND_PK> <USER_ADDR> <DNI>");
  process.exit(1);
}

const [, , backendPk, userAddr, dni] = process.argv;


const idHash = keccak256(toUtf8Bytes(dni));


const prefix = "\x19Ethereum Signed Message:\n84";
const digest = keccak256(
  concat([toUtf8Bytes(prefix), arrayify(userAddr), arrayify(idHash)])
);


const wallet = new Wallet(backendPk);
const sig    = joinSignature(wallet._signingKey().signDigest(digest));


console.log("idHash   =", idHash);
console.log("signature=", sig);
