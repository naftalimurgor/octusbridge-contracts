import { Ed25519KeyPair } from "nekoton-wasm";

import BigNumber from "bignumber.js";
const {
  setupBridge,
  setupEverscaleEthereumEventConfiguration,
  setupRelays,
  MetricManager,
  enableEventConfiguration,
  captureConnectors,
  logger,
  getTokenWalletByAddress,
} = require("../../../utils");

import { expect } from "chai";
import { Contract } from "locklift";
import { FactorySource } from "../../../../build/factorySource";
import { Account } from "everscale-standalone-client/nodejs";

let bridge: Contract<FactorySource["Bridge"]>;
let cellEncoder: Contract<FactorySource["CellEncoderStandalone"]>;
let staking: Contract<FactorySource["StakingMockup"]>;
let bridgeOwner: Account;
let metricManager: InstanceType<typeof MetricManager>;
let relays: Ed25519KeyPair[];
let everscaleEthereumEventConfiguration: Contract<
  FactorySource["EverscaleEthereumEventConfiguration"]
>;
let proxy: Contract<FactorySource["ProxyTokenTransfer"]>;
let initializer: Account;
let initializerTokenWallet: Contract<FactorySource["TokenWallet"]>;

describe("Test everscale ethereum event reject", async function () {
  this.timeout(10000000);

  afterEach(async function () {
    const lastCheckPoint = metricManager.lastCheckPointName();
    const currentName = this.currentTest?.title;

    await metricManager.checkPoint(currentName);

    if (lastCheckPoint === undefined) return;

    const difference = await metricManager.getDifference(
      lastCheckPoint,
      currentName
    );

    for (const [contract, balanceDiff] of Object.entries(difference)) {
      if (balanceDiff !== 0) {
        logger.log(
          `[Balance change] ${contract} ${locklift.utils.fromNano(
            balanceDiff as number
          )} Everscale`
        );
      }
    }
  });

  it("Setup bridge", async () => {
    relays = await setupRelays();

    [bridge, bridgeOwner, staking, cellEncoder] = await setupBridge(relays);

    [everscaleEthereumEventConfiguration, proxy, initializer] =
      await setupEverscaleEthereumEventConfiguration(
        bridgeOwner,
        staking,
        cellEncoder
      );

    metricManager = new MetricManager(
      bridge,
      bridgeOwner,
      staking,
      everscaleEthereumEventConfiguration,
      initializer
    );
  });

  describe("Enable event configuration", async () => {
    it("Add event configuration to bridge", async () => {
      await enableEventConfiguration(
        bridgeOwner,
        bridge,
        everscaleEthereumEventConfiguration,
        "ton"
      );
    });

    it("Check configuration enabled", async () => {
      const configurations = await captureConnectors(bridge);

      expect(configurations["0"]).to.be.not.equal(
        undefined,
        "Configuration not found"
      );

      expect(configurations["0"]._eventConfiguration).to.be.equal(
        everscaleEthereumEventConfiguration.address,
        "Wrong configuration address"
      );

      expect(configurations["0"]._enabled).to.be.equal(
        true,
        "Wrong connector status"
      );
    });
  });

  let tonEventParams: any;
  let tonEventValue: any;
  let burnPayload: any;
  let eventContract: Contract<
    FactorySource["TokenTransferEverscaleEthereumEvent"]
  >;

  describe("Initialize event", async () => {
    tonEventValue = 444;
    tonEventParams = {
      ethereumAddress: 222,
      chainId: 333,
    };

    it("Setup event data", async () => {
      initializerTokenWallet = await getTokenWalletByAddress(
        initializer.address,
        await proxy.methods.getTokenRoot({ answerId: 0 }).call()
      );

      burnPayload = await cellEncoder.methods
        .encodeEthereumBurnPayload(tonEventParams)
        .call()
        .then((t) => t.data);
    });

    it("Initialize event", async () => {
      const tx = await initializerTokenWallet.methods
        .burn({
          amount: tonEventValue,
          remainingGasTo: initializer.address,
          callbackTo: proxy.address,
          payload: burnPayload,
        })
        .send({
          from: initializer.address,
          amount: locklift.utils.toNano(4),
        });

      const events = await everscaleEthereumEventConfiguration
        .getPastEvents({ filter: "NewEventContract" })
        .then((e) => e.events);

      expect(events).to.have.lengthOf(
        1,
        "Everscale event configuration didnt deploy event"
      );

      const [
        {
          data: { eventContract: expectedEventContract },
        },
      ] = events;

      logger.log(`Expected event address: ${expectedEventContract}`);

      eventContract = await locklift.factory.getDeployedContract(
        "TokenTransferEverscaleEthereumEvent",
        expectedEventContract
      );
    });

    it("Check event initial state", async () => {
      const details = await eventContract.methods
        .getDetails({ answerId: 0 })
        .call();

      expect(details._eventInitData.configuration).to.be.equal(
        everscaleEthereumEventConfiguration.address,
        "Wrong event configuration"
      );

      expect(details._status).to.be.equal(1, "Wrong status");

      expect(details._confirms).to.have.lengthOf(
        0,
        "Wrong amount of confirmations"
      );

      expect(details._signatures).to.have.lengthOf(
        0,
        "Wrong amount of signatures"
      );

      expect(details._rejects).to.have.lengthOf(0, "Wrong amount of rejects");

      expect(details._initializer).to.be.equal(
        proxy.address,
        "Wrong initializer"
      );
    });

    it("Check encoded event data", async () => {
      const data = await eventContract.methods
        .getDecodedData({ answerId: 0 })
        .call();

      expect(data.owner_address).to.be.equal(
        initializer.address,
        "Wrong owner address"
      );

      expect(data.wid).to.be.equal(
        initializer.address.toString().split(":")[0],
        "Wrong wid"
      );

      expect(data.addr).to.be.equal(
        new BigNumber(initializer.address.toString().split(":")[1], 16),
        "Wrong address"
      );

      expect(data.tokens).to.be.equal(tonEventValue, "Wrong amount of tokens");

      expect(data.ethereum_address).to.be.equal(
        tonEventParams.ethereumAddress,
        "Wrong ethereum address"
      );

      expect(data.chainId).to.be.equal(
        tonEventParams.chainId,
        "Wrong chain id"
      );
    });
  });

  describe("Reject event", async () => {
    it("Reject event enough times", async () => {
      const requiredVotes = await eventContract.methods.requiredVotes().call();

      const rejects = [];
      for (const [relayId, relay] of Object.entries(
        relays.slice(0, parseInt(requiredVotes.requiredVotes, 10))
      )) {
        logger.log(`Reject #${relayId} from ${relay.publicKey}`);

        locklift.keystore.addKeyPair(relay);

        rejects.push(
          eventContract.methods
            .reject({
              voteReceiver: eventContract.address,
            })
            .sendExternal({
              publicKey: relay.publicKey,
            })
        );
      }
      await Promise.all(rejects);
    });

    it("Check event rejected", async () => {
      const details = await eventContract.methods
        .getDetails({ answerId: 0 })
        .call();

      const requiredVotes = await eventContract.methods.requiredVotes().call();

      expect(details.balance).to.be.greaterThan(0, "Wrong balance");

      expect(details._status).to.be.equal(3, "Wrong status");

      expect(details._confirms).to.have.lengthOf(
        0,
        "Wrong amount of relays confirmations"
      );

      expect(details._signatures).to.have.lengthOf(
        0,
        "Wrong amount of signatures"
      );

      expect(details._rejects).to.have.lengthOf(
        parseInt(requiredVotes.requiredVotes, 10),
        "Wrong amount of relays rejects"
      );
    });

    it("Send confirms from the rest of relays", async () => {
      const requiredVotes = await eventContract.methods.requiredVotes().call();

      for (const [relayId, relay] of Object.entries(
        relays.slice(parseInt(requiredVotes.requiredVotes, 10))
      )) {
        logger.log(
          `Reject #${
            parseInt(requiredVotes.requiredVotes, 10) + relayId
          } from ${relay.publicKey}`
        );

        locklift.keystore.addKeyPair(relay);

        await eventContract.methods
          .reject({
            voteReceiver: eventContract.address,
          })
          .sendExternal({
            publicKey: relay.publicKey,
          });
      }
    });

    it("Check event details after all relays voted", async () => {
      const details = await eventContract.methods
        .getDetails({ answerId: 0 })
        .call();

      expect(details.balance).to.be.greaterThan(0, "Wrong balance");

      expect(details._status).to.be.equal(3, "Wrong status");

      expect(details._confirms).to.have.lengthOf(
        0,
        "Wrong amount of relays confirmations"
      );

      expect(details._signatures).to.have.lengthOf(
        0,
        "Wrong amount of signatures"
      );

      expect(details._rejects).to.have.lengthOf(
        relays.length,
        "Wrong amount of relays rejects"
      );
    });

    it("Close event", async () => {
      await eventContract.methods.close({}).send({
        from: initializer.address,
        amount: locklift.utils.toNano(1),
      });

      const details = await eventContract.methods
        .getDetails({ answerId: 0 })
        .call();

      expect(details.balance).to.be.equal(0, "Wrong balance");
    });
  });
});
