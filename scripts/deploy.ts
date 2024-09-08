import { ContractFactory, getDefaultProvider, Wallet, ethers } from "ethers";
import { readFileSync } from "fs";

if (!process.env.PRIVATE_KEY) {
  console.log("Please export your PRIVATE_KEY");
  process.exit(1);
}

const test = false;

const provider = getDefaultProvider(
  test ? "https://sepolia.base.org" : "https://mainnet.base.org"
);

const signer = new Wallet(process.env.PRIVATE_KEY!, provider);

console.log("Wallet address:", signer.address);

let nonce = 49;

async function deployContract(name: string, constructorArgs: any[]) {
  const contractAbi = readFileSync(`./bin/${name}.abi`, "utf8");
  const contractByteCode = readFileSync(`./bin/${name}.bin`, "utf8");
  const factory = new ContractFactory(contractAbi, contractByteCode, signer);

  const overrides = {
    nonce: nonce++,
  };
  const contract = await factory.deploy(...constructorArgs, overrides);

  console.log(`${name}\n${contract.address}`);
  console.log("Waiting for contract to be deployed...");
  await contract.deployTransaction.wait();
  console.log("Contract deployed!\n");

  return contract;
}

// First, deploy Sorites contract
const soritesContract = await deployContract("Sorites", []);

// Then the SoritesPriceFuturesProvider contract
const priceFuturesContract = await deployContract(
  "SoritesPriceFuturesProvider",
  [soritesContract.address]
);

// Whitelist the SoritesPriceFuturesProvider contract in the Sorites contract
await soritesContract.functions.addFuturesContract(
  priceFuturesContract.address,
  {
    nonce: nonce++,
    gasLimit: ethers.utils.hexlify(1000000),
  }
);

// Get supported assets
const supportedPriceAssets = await fetch(
  test
    ? "https://reference-data-directory.vercel.app/feeds-ethereum-testnet-sepolia-base-1.json"
    : "https://reference-data-directory.vercel.app/feeds-ethereum-mainnet-base-1.json"
).then((res) => res.json());

for (const { name, contractAddress } of supportedPriceAssets) {
  if (!name.endsWith(" / USD")) continue;

  const asset = name.split(" / ")[0];
  const overrides = {
    nonce: nonce++,
    gasLimit: ethers.utils.hexlify(1000000),
  };

  await priceFuturesContract.functions.addSupportedAsset(
    asset,
    contractAddress,
    overrides
  );

  console.log("Added asset", asset);
}
