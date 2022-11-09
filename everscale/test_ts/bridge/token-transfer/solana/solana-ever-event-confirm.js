const {
  setupBridge,
  setupSolanaEverscaleEventConfiguration,
  setupRelays,
  MetricManager,
  enableEventConfiguration,
  captureConnectors,
  afterRun,
  logger,
  expect,
  getTokenWalletByAddress,
  getTokenRoot
} = require('../../../utils');
const BigNumber = require("bignumber.js");


describe('Test solana everscale event confirm', async function() {
  this.timeout(10000000);

  let bridge, bridgeOwner, staking, cellEncoder;
  let solanaEverscaleEventConfiguration, proxy, initializer;
  let relays;
  let metricManager;
  let initializerTokenWallet;

  afterEach(async function() {
    const lastCheckPoint = metricManager.lastCheckPointName();
    const currentName = this.currentTest.title;

    await metricManager.checkPoint(currentName);

    if (lastCheckPoint === undefined) return;

    const difference = await metricManager.getDifference(lastCheckPoint, currentName);

    for (const [contract, balanceDiff] of Object.entries(difference)) {
      if (balanceDiff !== 0) {
        logger.log(`[Balance change] ${contract} ${locklift.utils.fromNano(balanceDiff as number)} Everscale`);
      }
    }
  });

  it('Setup bridge', async () => {
    relays = await setupRelays();

    [bridge, bridgeOwner, staking, cellEncoder] = await setupBridge(relays);

    [solanaEverscaleEventConfiguration, proxy, initializer] = await setupSolanaEverscaleEventConfiguration(
      bridgeOwner,
      staking
    );

    initializerTokenWallet = await getTokenWalletByAddress(initializer.address, await proxy.call({method: 'getTokenRoot'}));
    initializerTokenWallet.name = 'Initializer TokenWallet'

    metricManager = new MetricManager(
      bridge, bridgeOwner, staking,
      solanaEverscaleEventConfiguration, proxy, initializer
    );
  });

  describe('Enable event configuration', async () => {
    it('Add event configuration to bridge', async () => {
      await enableEventConfiguration(
        bridgeOwner,
        bridge,
        solanaEverscaleEventConfiguration,
      );
    });

    it('Check configuration enabled', async () => {
      const configurations = await captureConnectors(bridge);

      expect(configurations['0'])
        .to.be.not.equal(undefined, 'Configuration not found');

      expect(configurations['0']._eventConfiguration)
        .to.be.equal(solanaEverscaleEventConfiguration.address, 'Wrong configuration address');

      expect(configurations['0']._enabled)
        .to.be.equal(true, 'Wrong connector status');
    });
  });

  let eventContract, eventVoteData, eventDataStructure;

  describe('Initialize event', async () => {

    it('Setup event data', async () => {

      eventDataStructure = {
        sender_addr: new BigNumber('42383474428106489994084969139012277140818210945614381322072008626484785752705').toFixed(),
        tokens: 100,
        receiver_addr: initializer.address
      };

      const eventData = await cellEncoder.call({
        method: 'encodeSolanaEverscaleEventData',
        params: eventDataStructure
      });

      eventVoteData = {
        accountSeed: 111,
        slot: 0,
        blockTime: 0,
        txSignature: '',
        eventData,
      };
    });

    it('Initialize event', async () => {
      const tx = await initializer.runTarget({
        contract: solanaEverscaleEventConfiguration,
        method: 'deployEvent',
        params: {
          eventVoteData,
        },
        value: locklift.utils.convertCrystal(6, 'nano')
      });

      logger.log(`Event initialization tx: ${tx.id}`);

      const expectedEventContract = await solanaEverscaleEventConfiguration.call({
        method: 'deriveEventAddress',
        params: {
          eventVoteData,
        }
      });

      logger.log(`Expected event address: ${expectedEventContract}`);

      eventContract = await locklift.factory.getContract('TokenTransferSolanaEverscaleEvent');
      eventContract.setAddress(expectedEventContract);
      eventContract.afterRun = afterRun;

      metricManager.addContract(eventContract);
    });

    it('Check event initial state', async () => {
      const details = await eventContract.methods.getDetails({answerId: 0}).call();

      expect(details._eventInitData.voteData.accountSeed)
        .to.be.bignumber.equal(eventVoteData.accountSeed, 'Wrong accountSeed');

      expect(details._eventInitData.voteData.eventData)
        .to.be.equal(eventVoteData.eventData, 'Wrong event data');

      expect(details._eventInitData.configuration)
        .to.be.equal(solanaEverscaleEventConfiguration.address, 'Wrong event configuration');

      expect(details._eventInitData.staking)
        .to.be.equal(staking.address, 'Wrong staking');

      expect(details._status)
        .to.be.bignumber.equal(1, 'Wrong status');

      expect(details._confirms)
        .to.have.lengthOf(0, 'Wrong amount of relays confirmations');

      expect(details._rejects)
        .to.have.lengthOf(0, 'Wrong amount of relays rejects');

      expect(details._initializer)
        .to.be.equal(initializer.address, 'Wrong initializer');
    });

    it('Check event required votes', async () => {
      const requiredVotes = await eventContract.methods.requiredVotes().call();


      const relays = await eventContract.methods.getVoters({
                vote: 1,
                answerId: 0
            }).call();

      expect(requiredVotes)
        .to.be.bignumber.greaterThan(0, 'Too low required votes for event');

      expect(relays.length)
        .to.be.bignumber.greaterThanOrEqual(parseInt(requiredVotes.requiredVotes, 10), 'Too many required votes for event');
    });

    it('Check event round number', async () => {
      const roundNumber = await eventContract.methods.round_number({}).call();

      expect(roundNumber)
        .to.be.bignumber.equal(0, 'Wrong round number');
    });

    it('Check encoded event data', async () => {
      const data = await eventContract.methods.getDecodedData({answerId: 0}).call();

      expect(data.tokens)
        .to.be.bignumber.equal(eventDataStructure.tokens, 'Wrong amount of tokens');

      expect(data.receiver_addr)
        .to.be.equal(eventDataStructure.receiver_addr, 'Wrong receiver address');
    });
  });

  describe('Confirm event', async () => {
    it('Confirm event enough times', async () => {
      const requiredVotes = await eventContract.methods.requiredVotes().call();


      const confirmations = [];
      for (const [relayId, relay] of Object.entries(relays.slice(0, requiredVotes))) {
        logger.log(`Confirm #${relayId} from ${relay.public}`);

        confirmations.push(eventContract.run({
          method: 'confirm',
          params: {
            voteReceiver: eventContract.address
          },
          keyPair: relay
        }));
      }
      await Promise.all(confirmations);
    });

    it('Check event confirmed', async () => {
      const details = await eventContract.methods.getDetails({answerId: 0}).call();

      const requiredVotes = await eventContract.methods.requiredVotes().call();


      // expect(details.balance)
      //   .to.be.bignumber.equal(0, 'Wrong balance');

      expect(details._status)
        .to.be.bignumber.equal(2, 'Wrong status');

      expect(details._confirms)
        .to.have.lengthOf(requiredVotes, 'Wrong amount of relays confirmations');

      expect(details._rejects)
        .to.have.lengthOf(0, 'Wrong amount of relays rejects');
    });

    it('Check event proxy minted tokens', async () => {
      expect(await initializerTokenWallet.methods.balance({answerId: 0}).call())
        .to.be.bignumber.equal(eventDataStructure.tokens, 'Wrong initializerTokenWallet balance');
    });
  });
});
