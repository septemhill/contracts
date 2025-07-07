import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const DeployP2PAndTokensModule = buildModule("DeployP2PAndTokensModule", (m) => {
  // Get the deployer account (account at index 0)
  const deployer = m.getAccount(0);

  const initialSupply = 1_000_000n;

  // Deploy Token A and Token B contracts from the deployer's account
  const tokenA = m.contract("TestToken", ["Token A", "TKA", initialSupply], {
    id: "TokenA",
    from: deployer,
  });
  const tokenB = m.contract("TestToken", ["Token B", "TKB", initialSupply], {
    id: "TokenB",
    from: deployer,
  });

  // Deploy the P2PExchange contract
  const exchange = m.contract("P2PExchange", [], {
    from: deployer,
  });

  // === Token Distribution ===
  // The TestToken contract mints the entire initialSupply to the deployer.
  // We will now distribute the tokens evenly among the first 5 accounts.

  const distributionAccountsCount = 5;
  const amountPerAccount = initialSupply / BigInt(distributionAccountsCount);

  // We transfer tokens from the deployer (account 0) to the other 4 accounts.
  // The loop starts at 1 because account 0 is the deployer and already has the tokens.
  for (let i = 1; i < distributionAccountsCount; i++) {
    const toAccount = m.getAccount(i);

    // Transfer Token A from the deployer to the recipient account
    m.call(tokenA, "transfer", [toAccount, amountPerAccount], {
      id: `TransferA_To_Account${i}`, // Unique ID for the transaction
      from: deployer,
    });

    // Transfer Token B from the deployer to the recipient account
    m.call(tokenB, "transfer", [toAccount, amountPerAccount], {
      id: `TransferB_To_Account${i}`, // Unique ID for the transaction
      from: deployer,
    });
  }

  return { tokenA, tokenB, exchange };
});

export default DeployP2PAndTokensModule;
