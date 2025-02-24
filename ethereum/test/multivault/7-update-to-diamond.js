const {
    encodeEverscaleEvent,
    expect,
    ...utils
} = require("../utils");
const {ethers} = require("hardhat");
const _ = require("lodash");


const MULTIVAULT = '0x54c55369a6900731d22eacb0df7c0253cf19dfff';
const PROXY_ADMIN = '0x5889d26Ad270540E315B028Dd39Ae0ECB3De6179';
const MULTIVAULT_ABI = [{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"base_chainId","type":"uint256"},{"indexed":false,"internalType":"uint160","name":"base_token","type":"uint160"},{"indexed":false,"internalType":"string","name":"name","type":"string"},{"indexed":false,"internalType":"string","name":"symbol","type":"string"},{"indexed":false,"internalType":"uint8","name":"decimals","type":"uint8"},{"indexed":false,"internalType":"uint128","name":"amount","type":"uint128"},{"indexed":false,"internalType":"int8","name":"recipient_wid","type":"int8"},{"indexed":false,"internalType":"uint256","name":"recipient_addr","type":"uint256"}],"name":"AlienTransfer","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"token","type":"address"}],"name":"BlacklistTokenAdded","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"token","type":"address"}],"name":"BlacklistTokenRemoved","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"enum IMultiVault.TokenType","name":"_type","type":"uint8"},{"indexed":false,"internalType":"address","name":"sender","type":"address"},{"indexed":false,"internalType":"address","name":"token","type":"address"},{"indexed":false,"internalType":"int8","name":"recipient_wid","type":"int8"},{"indexed":false,"internalType":"uint256","name":"recipient_addr","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"fee","type":"uint256"}],"name":"Deposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"bool","name":"active","type":"bool"}],"name":"EmergencyShutdown","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"int8","name":"native_wid","type":"int8"},{"indexed":false,"internalType":"uint256","name":"native_addr","type":"uint256"},{"indexed":false,"internalType":"uint128","name":"amount","type":"uint128"},{"indexed":false,"internalType":"int8","name":"recipient_wid","type":"int8"},{"indexed":false,"internalType":"uint256","name":"recipient_addr","type":"uint256"}],"name":"NativeTransfer","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"governance","type":"address"}],"name":"NewPendingGovernance","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"recipient","type":"address"},{"indexed":false,"internalType":"uint256","name":"id","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"PendingWithdrawalCancel","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"recipient","type":"address"},{"indexed":false,"internalType":"uint256","name":"id","type":"uint256"},{"indexed":false,"internalType":"address","name":"token","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"},{"indexed":false,"internalType":"bytes32","name":"payloadId","type":"bytes32"}],"name":"PendingWithdrawalCreated","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"recipient","type":"address"},{"indexed":false,"internalType":"uint256","name":"id","type":"uint256"}],"name":"PendingWithdrawalFill","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"recipient","type":"address"},{"indexed":false,"internalType":"uint256","name":"id","type":"uint256"}],"name":"PendingWithdrawalForce","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"recipient","type":"address"},{"indexed":false,"internalType":"uint256","name":"id","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"bounty","type":"uint256"}],"name":"PendingWithdrawalUpdateBounty","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"recipient","type":"address"},{"indexed":false,"internalType":"uint256","name":"id","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"PendingWithdrawalWithdraw","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"token","type":"address"},{"indexed":false,"internalType":"bool","name":"skim_to_everscale","type":"bool"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"SkimFee","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"token","type":"address"},{"indexed":false,"internalType":"uint256","name":"activation","type":"uint256"},{"indexed":false,"internalType":"bool","name":"isNative","type":"bool"},{"indexed":false,"internalType":"uint256","name":"depositFee","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"withdrawFee","type":"uint256"}],"name":"TokenActivated","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"token","type":"address"},{"indexed":false,"internalType":"int8","name":"native_wid","type":"int8"},{"indexed":false,"internalType":"uint256","name":"native_addr","type":"uint256"},{"indexed":false,"internalType":"string","name":"name_prefix","type":"string"},{"indexed":false,"internalType":"string","name":"symbol_prefix","type":"string"},{"indexed":false,"internalType":"string","name":"name","type":"string"},{"indexed":false,"internalType":"string","name":"symbol","type":"string"},{"indexed":false,"internalType":"uint8","name":"decimals","type":"uint8"}],"name":"TokenCreated","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"token","type":"address"},{"indexed":false,"internalType":"address","name":"vault","type":"address"}],"name":"TokenMigrated","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"bridge","type":"address"}],"name":"UpdateBridge","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"enum IMultiVault.TokenType","name":"_type","type":"uint8"},{"indexed":false,"internalType":"int128","name":"wid","type":"int128"},{"indexed":false,"internalType":"uint256","name":"addr","type":"uint256"}],"name":"UpdateConfiguration","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"fee","type":"uint256"}],"name":"UpdateDefaultAlienDepositFee","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"fee","type":"uint256"}],"name":"UpdateDefaultAlienWithdrawFee","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"fee","type":"uint256"}],"name":"UpdateDefaultNativeDepositFee","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"uint256","name":"fee","type":"uint256"}],"name":"UpdateDefaultNativeWithdrawFee","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"governance","type":"address"}],"name":"UpdateGovernance","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"guardian","type":"address"}],"name":"UpdateGuardian","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"management","type":"address"}],"name":"UpdateManagement","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"int128","name":"wid","type":"int128"},{"indexed":false,"internalType":"uint256","name":"addr","type":"uint256"}],"name":"UpdateRewards","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"token","type":"address"},{"indexed":false,"internalType":"uint256","name":"fee","type":"uint256"}],"name":"UpdateTokenDepositFee","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"token","type":"address"},{"indexed":false,"internalType":"string","name":"name_prefix","type":"string"},{"indexed":false,"internalType":"string","name":"symbol_prefix","type":"string"}],"name":"UpdateTokenPrefix","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"address","name":"token","type":"address"},{"indexed":false,"internalType":"uint256","name":"fee","type":"uint256"}],"name":"UpdateTokenWithdrawFee","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"internalType":"enum IMultiVault.TokenType","name":"_type","type":"uint8"},{"indexed":false,"internalType":"bytes32","name":"payloadId","type":"bytes32"},{"indexed":false,"internalType":"address","name":"token","type":"address"},{"indexed":false,"internalType":"address","name":"recipient","type":"address"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"fee","type":"uint256"}],"name":"Withdraw","type":"event"},{"inputs":[],"name":"acceptGovernance","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"apiVersion","outputs":[{"internalType":"string","name":"api_version","type":"string"}],"stateMutability":"pure","type":"function"},{"inputs":[{"internalType":"address","name":"token","type":"address"}],"name":"blacklistAddToken","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"token","type":"address"}],"name":"blacklistRemoveToken","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"bridge","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"address","name":"_token","type":"address"},{"internalType":"enum IMultiVault.Fee","name":"fee","type":"uint8"}],"name":"calculateMovementFee","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"id","type":"uint256"},{"internalType":"uint256","name":"amount","type":"uint256"},{"components":[{"internalType":"int8","name":"wid","type":"int8"},{"internalType":"uint256","name":"addr","type":"uint256"}],"internalType":"struct IEverscale.EverscaleAddress","name":"recipient","type":"tuple"},{"internalType":"uint256","name":"bounty","type":"uint256"}],"name":"cancelPendingWithdrawal","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"configurationAlien","outputs":[{"components":[{"internalType":"int8","name":"wid","type":"int8"},{"internalType":"uint256","name":"addr","type":"uint256"}],"internalType":"struct IEverscale.EverscaleAddress","name":"","type":"tuple"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"configurationNative","outputs":[{"components":[{"internalType":"int8","name":"wid","type":"int8"},{"internalType":"uint256","name":"addr","type":"uint256"}],"internalType":"struct IEverscale.EverscaleAddress","name":"","type":"tuple"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"defaultAlienDepositFee","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"defaultAlienWithdrawFee","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"defaultNativeDepositFee","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"defaultNativeWithdrawFee","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"components":[{"internalType":"int8","name":"wid","type":"int8"},{"internalType":"uint256","name":"addr","type":"uint256"}],"internalType":"struct IEverscale.EverscaleAddress","name":"recipient","type":"tuple"},{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"deposit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"components":[{"internalType":"int8","name":"wid","type":"int8"},{"internalType":"uint256","name":"addr","type":"uint256"}],"internalType":"struct IEverscale.EverscaleAddress","name":"recipient","type":"tuple"},{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"uint256","name":"expectedMinBounty","type":"uint256"},{"components":[{"internalType":"address","name":"recipient","type":"address"},{"internalType":"uint256","name":"id","type":"uint256"}],"internalType":"struct IMultiVault.PendingWithdrawalId[]","name":"pendingWithdrawalIds","type":"tuple[]"}],"name":"deposit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"emergencyShutdown","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"fees","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"components":[{"internalType":"address","name":"recipient","type":"address"},{"internalType":"uint256","name":"id","type":"uint256"}],"internalType":"struct IMultiVault.PendingWithdrawalId[]","name":"pendingWithdrawalIds","type":"tuple[]"}],"name":"forceWithdraw","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"getChainID","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"getInitHash","outputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"stateMutability":"pure","type":"function"},{"inputs":[{"internalType":"int8","name":"native_wid","type":"int8"},{"internalType":"uint256","name":"native_addr","type":"uint256"}],"name":"getNativeToken","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"governance","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"guardian","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_bridge","type":"address"},{"internalType":"address","name":"_governance","type":"address"}],"name":"initialize","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"management","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"token","type":"address"},{"internalType":"address","name":"vault","type":"address"}],"name":"migrateAlienTokenToVault","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_token","type":"address"}],"name":"natives","outputs":[{"components":[{"internalType":"int8","name":"wid","type":"int8"},{"internalType":"uint256","name":"addr","type":"uint256"}],"internalType":"struct IEverscale.EverscaleAddress","name":"","type":"tuple"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"user","type":"address"},{"internalType":"uint256","name":"id","type":"uint256"}],"name":"pendingWithdrawals","outputs":[{"components":[{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"uint256","name":"bounty","type":"uint256"}],"internalType":"struct IMultiVault.PendingWithdrawalParams","name":"","type":"tuple"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"pendingWithdrawalsPerUser","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"","type":"address"}],"name":"pendingWithdrawalsTotal","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"_token","type":"address"}],"name":"prefixes","outputs":[{"components":[{"internalType":"uint256","name":"activation","type":"uint256"},{"internalType":"string","name":"name","type":"string"},{"internalType":"string","name":"symbol","type":"string"}],"internalType":"struct IMultiVault.TokenPrefix","name":"","type":"tuple"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"rewards","outputs":[{"components":[{"internalType":"int8","name":"wid","type":"int8"},{"internalType":"uint256","name":"addr","type":"uint256"}],"internalType":"struct IEverscale.EverscaleAddress","name":"","type":"tuple"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes","name":"payload","type":"bytes"},{"internalType":"bytes[]","name":"signatures","type":"bytes[]"}],"name":"saveWithdrawAlien","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"bytes","name":"payload","type":"bytes"},{"internalType":"bytes[]","name":"signatures","type":"bytes[]"},{"internalType":"uint256","name":"bounty","type":"uint256"}],"name":"saveWithdrawAlien","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"bytes","name":"payload","type":"bytes"},{"internalType":"bytes[]","name":"signatures","type":"bytes[]"}],"name":"saveWithdrawNative","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"components":[{"internalType":"int8","name":"wid","type":"int8"},{"internalType":"uint256","name":"addr","type":"uint256"}],"internalType":"struct IEverscale.EverscaleAddress","name":"_configuration","type":"tuple"}],"name":"setConfigurationAlien","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"components":[{"internalType":"int8","name":"wid","type":"int8"},{"internalType":"uint256","name":"addr","type":"uint256"}],"internalType":"struct IEverscale.EverscaleAddress","name":"_configuration","type":"tuple"}],"name":"setConfigurationNative","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"fee","type":"uint256"}],"name":"setDefaultAlienDepositFee","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"fee","type":"uint256"}],"name":"setDefaultAlienWithdrawFee","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"fee","type":"uint256"}],"name":"setDefaultNativeDepositFee","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"fee","type":"uint256"}],"name":"setDefaultNativeWithdrawFee","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"bool","name":"active","type":"bool"}],"name":"setEmergencyShutdown","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_governance","type":"address"}],"name":"setGovernance","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_guardian","type":"address"}],"name":"setGuardian","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_management","type":"address"}],"name":"setManagement","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"id","type":"uint256"},{"internalType":"uint256","name":"bounty","type":"uint256"}],"name":"setPendingWithdrawalBounty","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"token","type":"address"},{"internalType":"string","name":"name_prefix","type":"string"},{"internalType":"string","name":"symbol_prefix","type":"string"}],"name":"setPrefix","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"components":[{"internalType":"int8","name":"wid","type":"int8"},{"internalType":"uint256","name":"addr","type":"uint256"}],"internalType":"struct IEverscale.EverscaleAddress","name":"_rewards","type":"tuple"}],"name":"setRewards","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"_depositFee","type":"uint256"}],"name":"setTokenDepositFee","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"token","type":"address"},{"internalType":"uint256","name":"_withdrawFee","type":"uint256"}],"name":"setTokenWithdrawFee","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"token","type":"address"},{"internalType":"bool","name":"skim_to_everscale","type":"bool"}],"name":"skim","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_token","type":"address"}],"name":"tokens","outputs":[{"components":[{"internalType":"uint256","name":"activation","type":"uint256"},{"internalType":"bool","name":"blacklisted","type":"bool"},{"internalType":"uint256","name":"depositFee","type":"uint256"},{"internalType":"uint256","name":"withdrawFee","type":"uint256"},{"internalType":"bool","name":"isNative","type":"bool"}],"internalType":"struct IMultiVault.Token","name":"","type":"tuple"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"bytes32","name":"","type":"bytes32"}],"name":"withdrawalIds","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"}];

const NATIVE_TOKEN = '0xa8e72ea582d93a42fecb705a8a931a59d8fec063';

describe('Test upgrading Ethereum MultiVault to the Diamond proxy', async () => {
    let multivault, token, state;
    let diamond_multivault;
    let multisig;

    it('Setup contracts', async () => {
        await deployments.fixture();

        multivault = await ethers.getContractAt(MULTIVAULT_ABI, MULTIVAULT);
        token = await ethers.getContract('Token');
    });

    it('Remember previous state', async () => {
        const governance = await multivault.governance();
        const rewards = await multivault.rewards();
        const configurationNative = await multivault.configurationNative();
        const initHash = await multivault.getInitHash();
        const nativeToken = await multivault.tokens(NATIVE_TOKEN);

        state = {
            governance,
            rewards,
            initHash,
            configurationNative,
            nativeToken
        };

        // console.log(state);
    });

    it('Upgrade proxy implementation to the Diamond', async () => {
        multisig = await ethers.getNamedSigner('multisig');

        const Diamond = await ethers.getContractFactory('Diamond');
        const diamond = await Diamond.deploy();

        const proxyAdmin = await ethers.getContractAt('contracts/multivault/proxy/ProxyAdmin.sol:ProxyAdmin', PROXY_ADMIN);

        const {
            data: diamondInitialize
        } = await diamond.populateTransaction.initialize(multisig.address);

        await proxyAdmin
            .connect(multisig)
            .upgradeAndCall(
                multivault.address,
                diamond.address,
                diamondInitialize
            );
    });

    it('Set up facets', async () => {
        const facets = [
            'MultiVaultFacetDeposit',
            'MultiVaultFacetFees',
            'MultiVaultFacetPendingWithdrawals',
            'MultiVaultFacetSettings',
            'MultiVaultFacetTokens',
            'MultiVaultFacetWithdraw',
            'MultiVaultFacetLiquidity'
        ];

        const facetCuts = await Promise.all(facets.map(async (name) => {
            const facet = await ethers.getContract(name);

            const functionSelectors = Object.entries(facet.interface.functions).map(([function_name, fn]) => {
                return ethers.utils.Interface.getSighash(fn);
            });

            return {
                facetAddress: facet.address,
                action: 0,
                functionSelectors
            };
        }));

        const diamondABI = await [
            ...facets,
            'DiamondCutFacet', 'DiamondLoupeFacet', 'DiamondOwnershipFacet'
        ].reduce(async (acc, name) => {
            const facet = await deployments.getExtendedArtifact(name);

            return [...await acc, ...facet.abi];
        }, []);

        diamond_multivault = await ethers.getContractAt(_.uniqWith(diamondABI, _.isEqual), MULTIVAULT);

        await diamond_multivault
            .connect(multisig)
            .diamondCut(
                facetCuts,
                ethers.constants.AddressZero,
                '0x'
            );
    });

    it('Validate new storage', async () => {
        const governance = await diamond_multivault.governance();
        const rewards = await diamond_multivault.rewards();
        const configurationNative = await diamond_multivault.configurationNative();
        const initHash = await diamond_multivault.getInitHash();
        const nativeToken = await diamond_multivault.tokens(NATIVE_TOKEN);

        expect(governance)
            .to.be.equal(state.governance, 'Wrong governance');

        expect(rewards.wid)
            .to.be.equal(state.rewards.wid, 'Wrong rewards');
        expect(rewards.addr)
            .to.be.equal(state.rewards.addr, 'Wrong rewards');

        expect(configurationNative.wid)
            .to.be.equal(state.configurationNative.wid, 'Wrong native configuration');
        expect(configurationNative.addr)
            .to.be.equal(state.configurationNative.addr, 'Wrong native configuration');

        expect(initHash)
            .to.be.equal(state.initHash, 'Wrong init hash');

        expect(nativeToken.activation)
            .to.be.equal(state.nativeToken.activation, 'Wrong native token activation');
        expect(nativeToken.blacklisted)
            .to.be.equal(state.nativeToken.blacklisted, 'Wrong native token blacklisted');
        expect(nativeToken.depositFee)
            .to.be.equal(state.nativeToken.depositFee, 'Wrong native token deposit fee');
        expect(nativeToken.withdrawFee)
            .to.be.equal(state.nativeToken.withdrawFee, 'Wrong native token withdraw fee');
        expect(nativeToken.isNative)
            .to.be.equal(state.nativeToken.isNative, 'Wrong native token isNative flag');
        expect(nativeToken.custom)
            .to.be.equal(ethers.constants.AddressZero, 'Wrong native token custom');

        expect(await diamond_multivault.gasDonor())
            .to.be.equal(ethers.constants.AddressZero, 'Wrong gas donor');
    });

    it('Check re-initialization multivault fails', async () => {
        await expect(
            diamond_multivault
                .connect(multisig)
                .initialize(
                    ethers.constants.AddressZero,
                    ethers.constants.AddressZero,
                    ethers.constants.AddressZero
                )
        )
            .to.be.revertedWith("Initializable: contract is already initialized");
    });
});
