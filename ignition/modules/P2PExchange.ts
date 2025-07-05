import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const P2PExchangeModule = buildModule("P2PExchangeModule", (m) => {
  const exchange = m.contract("P2PExchange");

  return { exchange };
});

export default P2PExchangeModule;
