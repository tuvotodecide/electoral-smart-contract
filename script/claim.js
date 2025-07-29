
const { ethers } = require("ethers");
require("dotenv").config(); 
async function main() {
  const RPC      = process.env.RPC_URL;
  const USER_PK  = process.env.USER_PK;
  const KYC_ADDR = process.env.KYC_REGISTRY;
  const IDHASH   = process.env.IDHASH;
  const SIG      = process.env.SIG;

  const provider = new ethers.providers.JsonRpcProvider(RPC);
  const wallet   = new ethers.Wallet(USER_PK, provider);
  const abi = [
    "function claim(bytes32 idHash, bytes calldata sig) external",
    "function balanceOf(address) view returns (uint256)"
  ];
  const kyc = new ethers.Contract(KYC_ADDR, abi, wallet);

  console.log(">>> Llamando claim()…");
  const tx = await kyc.claim(IDHASH, SIG);
  console.log("TxHash:", tx.hash);
  await tx.wait();
  const bal = await kyc.balanceOf(wallet.address);
  console.log("balanceOf user:", bal.toString());
}

main().catch((e)=>{ console.error(e); process.exit(1); });
