pragma ton-solidity ^0.39.0;
pragma AbiHeader expire;
pragma AbiHeader pubkey;

import "./../interfaces/IRootTokenContract.sol";
import "./../interfaces/ITONTokenWallet.sol";
import "./../interfaces/ITokensReceivedCallback.sol";
import "./../interfaces/IUserData.sol";
import "./../interfaces/IUpgradableByRequest.sol";
import "./../interfaces/IStakingPool.sol";
import "./../interfaces/IStakingDao.sol";
import "./../interfaces/IRelayRound.sol";
import "./../interfaces/IElection.sol";

import "./../UserData.sol";
import "./../Election.sol";
import "./../RelayRound.sol";

import "./../libraries/PlatformTypes.sol";
import "./../../utils/ErrorCodes.sol";
import "./../libraries/Gas.sol";

import "../../../../node_modules/@broxus/contracts/contracts/libraries/MsgFlag.sol";
import "../../../../node_modules/@broxus/contracts/contracts/platform/Platform.sol";
import "../../utils/Delegate.sol";

abstract contract StakingPoolBase is ITokensReceivedCallback, IStakingPool, IStakingDao, Delegate {
    // Events
    event RewardDeposit(uint128 amount, uint32 reward_round_num);
    event Deposit(address user, uint128 amount);
    event Withdraw(address user, uint128 amount);
    event RewardClaimed(address user, uint128 reward_tokens);
    event NewRewardRound(uint32 round_num);

    event ElectionStarted(uint32 round_num, uint32 election_start_time, address election_addr);
    event ElectionEnded(uint32 round_num, uint32 relay_requests, bool min_relays_ok);
    event RelayRoundInitialized(
        uint32 round_num,
        uint32 round_start_time,
        uint32 round_end_time,
        address round_addr,
        uint32 relays_count,
        bool duplicate
    );
    event RelaySlashed(address user, uint128 tokens_withdrawn);

    event DepositReverted(address user, uint128 amount);

    event DaoRootUpdated(address new_dao_root);
    event BridgeEventConfigUpdated(address new_bridge_event_config);
    event BridgeEventProxyUpdated(address new_bridge_event_proxy);
    event AdminUpdated(address new_admin);
    event RewarderUpdated(address new_rewarder);

    event ActiveUpdated(bool active);

    event RequestedUserDataUpgrade(address user);
    event RequestedElectionUpgrade(uint32 round_num);
    event RequestedRelayRoundUpgrade(uint32 round_num);

    event UserDataCodeUpgraded(uint32 code_version);
    event ElectionCodeUpgraded(uint32 code_version);
    event RelayRoundCodeUpgraded(uint32 code_version);

    event RelayConfigUpdated(
        uint32 relay_lock_time,
        uint32 relay_round_time,
        uint32 election_time,
        uint32 time_before_election,
        uint32 relays_count,
        uint32 min_relays_count,
        uint128 min_relay_deposit,
        uint128 relay_initial_deposit
    );

    uint32 static deploy_nonce;
    address static deployer;

    TvmCell platform_code;
    bool has_platform_code;

    TvmCell user_data_code;
    uint32 user_data_version;

    TvmCell election_code;
    uint32 election_version;

    TvmCell relay_round_code;
    uint32 relay_round_version;

    address dao_root;

    address bridge_event_config;

    address bridge_event_proxy;

    bool active;

    bool originRelayRoundInitialized;

    uint32 currentRelayRound;

    // time when current round have started
    uint32 currentRelayRoundStartTime;

    // time when current election have started
    uint32 currentElectionStartTime;

    // we need this for deriving relay round from timestamp
    uint32 prevRelayRoundEndTime;

    // 0 means no pending relay round
    uint32 pendingRelayRound;

    RewardRound[] rewardRounds;

    uint32 lastRewardTime;

    address tokenRoot;

    address tokenWallet;

    uint128 tokenBalance;

    uint128 rewardTokenBalance;

    address admin;

    address rewarder;

    uint128 rewardPerSecond = 1000000;

    uint32 relayLockTime = 30 days;

    uint32 relayRoundTime = 7 days;

    uint32 electionTime = 2 days;

    // election should start at lest after this much time before round end
    uint32 timeBeforeElection = 4 days;

    uint32 relaysCount = 30;

    uint32 minRelaysCount = 13;

    uint128 minRelayDeposit = 100000 * 10**9;

    uint128 relayInitialDeposit = 500 ton;

    // payloads for token receive callback
    uint8 constant STAKE_DEPOSIT = 0;
    uint8 constant REWARD_UP = 1;

    uint8 constant RELAY_PACK_SIZE = 30;

    struct PendingDeposit {
        address user;
        uint128 amount;
        address send_gas_to;
    }

    uint64 deposit_nonce = 0;
    // this is used to prevent data loss on bounced messages during deposit
    mapping (uint64 => PendingDeposit) deposits;

    function getDetails() public view responsible returns (BaseDetails) {
        return{ value: 0, flag: MsgFlag.REMAINING_GAS }BaseDetails(
            dao_root, bridge_event_config, bridge_event_proxy, tokenRoot, tokenWallet,
            admin, rewarder, tokenBalance, rewardTokenBalance,
            rewardPerSecond, lastRewardTime, rewardRounds
        );
    }

    function getCodeData() public view responsible returns (CodeData) {
        return{ value: 0, flag: MsgFlag.REMAINING_GAS }CodeData(
            platform_code, has_platform_code,
            user_data_code, user_data_version,
            election_code, election_version,
            relay_round_code, relay_round_version
        );
    }

    function getRelayRoundsDetails() public view responsible returns (RelayRoundsDetails) {
        return{ value: 0, flag: MsgFlag.REMAINING_GAS }RelayRoundsDetails(
            originRelayRoundInitialized, currentRelayRound, currentRelayRoundStartTime,
            currentElectionStartTime, prevRelayRoundEndTime, pendingRelayRound
        );
    }

    function getRelayConfig() public view responsible returns (RelayConfigDetails) {
        return{ value: 0, flag: MsgFlag.REMAINING_GAS }RelayConfigDetails(
            relayLockTime, relayRoundTime, electionTime, timeBeforeElection,
            relaysCount, minRelaysCount, minRelayDeposit, relayInitialDeposit
        );
    }

    function addDelegate(address addr, uint callHash) public onlyAdmin {
        optional(uint[]) optDelegate = delegators.fetch(addr);
        if (optDelegate.hasValue()) {
            uint[] delegate = optDelegate.get();
            delegate.push(callHash);
            delegators[addr] = delegate;
        } else {
            delegators[addr] = [callHash];
        }
    }

    function _reserve() internal view returns (uint128) {
        return math.max(address(this).balance - msg.value, Gas.ROOT_INITIAL_BALANCE);
    }

    function setDaoRoot(address new_dao_root, address send_gas_to) external onlyDaoRoot {
        tvm.rawReserve(_reserve(), 2);
        emit DaoRootUpdated(new_dao_root);
        dao_root = new_dao_root;
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function setBridgeEventConfig(address new_bridge_event_config, address send_gas_to) external onlyAdmin {
        tvm.rawReserve(_reserve(), 2);
        emit BridgeEventConfigUpdated(new_bridge_event_config);
        bridge_event_config = new_bridge_event_config;
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function setBridgeEventProxy(address new_bridge_event_proxy, address send_gas_to) external onlyAdmin {
        tvm.rawReserve(_reserve(), 2);
        emit BridgeEventProxyUpdated(new_bridge_event_proxy);
        bridge_event_proxy = new_bridge_event_proxy;
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function setAdmin(address new_admin, address send_gas_to) external onlyDaoRoot {
        tvm.rawReserve(_reserve(), 2);
        emit AdminUpdated(new_admin);
        admin = new_admin;
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function setRewarder(address new_rewarder, address send_gas_to) external onlyDaoRoot {
        tvm.rawReserve(_reserve(), 2);
        emit RewarderUpdated(new_rewarder);
        rewarder = new_rewarder;
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    // Active
    function setActive(bool new_active, address send_gas_to) external onlyAdmin {
        tvm.rawReserve(_reserve(), 2);
        if (
            new_active
            && dao_root.value != 0
            && bridge_event_config.value != 0
            && bridge_event_proxy.value != 0
            && has_platform_code
            && user_data_version > 0
            && election_version > 0
            && relay_round_version > 0
        ) {
            active = true;
        } else {
            active = false;
        }
        emit ActiveUpdated(active);
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    function isActive() external view responsible returns (bool) {
        return{ value: 0, flag: MsgFlag.REMAINING_GAS } active;
    }

    function setRelayConfig(
        uint32 relay_lock_time,
        uint32 relay_round_time,
        uint32 election_time,
        uint32 time_before_election,
        uint32 relays_count,
        uint32 min_relays_count,
        uint128 min_relay_deposit,
        uint128 relay_initial_deposit,
        address send_gas_to
    ) external onlyDaoRoot {
        tvm.rawReserve(_reserve(), 2);

        relayLockTime = relay_lock_time;
        relayRoundTime = relay_round_time;
        electionTime = election_time;
        timeBeforeElection = time_before_election;
        relaysCount = relays_count;
        minRelaysCount = min_relays_count;
        minRelayDeposit = min_relay_deposit;
        relayInitialDeposit = relay_initial_deposit;

        emit RelayConfigUpdated(
            relay_lock_time,
            relay_round_time,
            election_time,
            time_before_election,
            relays_count,
            min_relays_count,
            min_relay_deposit,
            relay_initial_deposit
        );
        send_gas_to.transfer({ value: 0, bounce: false, flag: MsgFlag.ALL_NOT_RESERVED });
    }

    /*
        @notice Creates token wallet for configured root token
    */
    function setUpTokenWallets() internal view {
        // Deploy vault's token wallet
        IRootTokenContract(tokenRoot).deployEmptyWallet{value: Gas.TOKEN_WALLET_DEPLOY_VALUE}(
            Gas.TOKEN_WALLET_DEPLOY_VALUE / 2, // deploy grams
            0, // owner pubkey
            address(this), // owner address
            address(this) // gas refund address
        );

        // Request for token wallet address
        IRootTokenContract(tokenRoot).getWalletAddress{
            value: Gas.GET_WALLET_ADDRESS_VALUE, callback: StakingPoolBase.receiveTokenWalletAddress
        }(0, address(this));
    }

    /*
        @notice Store vault's token wallet address
        @dev Only root can call with correct params
        @param wallet Farm pool's token wallet
    */
    function receiveTokenWalletAddress(address wallet) external {
        if (msg.sender == tokenRoot) {
            tokenWallet = wallet;
            ITONTokenWallet(wallet).setReceiveCallback{value: 0.05 ton}(address(this), false);
        }
    }

    function startNewRewardRound(address send_gas_to) external onlyRewarder {
        require (msg.value >= Gas.MIN_START_REWARD_ROUND_MSG_VALUE, ErrorCodes.VALUE_TOO_LOW);

        if (rewardRounds.length > 0) {
            RewardRound last_round = rewardRounds[rewardRounds.length - 1];
            require (last_round.rewardTokens > 0, ErrorCodes.EMPTY_REWARD_ROUND);
        }

        tvm.rawReserve(_reserve(), 2);

        updatePoolInfo();

        rewardRounds.push(RewardRound(0, 0, 0, now));
        emit NewRewardRound(uint32(rewardRounds.length - 1));

        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    // deposit occurs here
    function tokensReceivedCallback(
        address /*token_wallet*/,
        address /*token_root*/,
        uint128 amount,
        uint256 /*sender_public_key*/,
        address sender_address,
        address sender_wallet,
        address original_gas_to,
        uint128 /*updated_balance*/,
        TvmCell payload
    ) external override {
        tvm.rawReserve(_reserve(), 2);

        TvmSlice slice = payload.toSlice();
        uint8 deposit_type = slice.decode(uint8);

        if (msg.sender == tokenWallet) {
            if (sender_address.value == 0 || msg.value < Gas.MIN_DEPOSIT_MSG_VALUE || !active) {
                // external owner or too low msg.value
                TvmCell tvmcell;
                ITONTokenWallet(tokenWallet).transfer{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                    sender_wallet,
                    amount,
                    0,
                    original_gas_to,
                    false,
                    tvmcell
                );
                return;
            }

            updatePoolInfo();

            if (deposit_type == STAKE_DEPOSIT) {
                deposit_nonce += 1;
                deposits[deposit_nonce] = PendingDeposit(sender_address, amount, original_gas_to);

                address userDataAddr = getUserDataAddress(sender_address);
                UserData(userDataAddr).processDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(deposit_nonce, amount, rewardRounds, user_data_version);
            } else if (deposit_type == REWARD_UP) {
                rewardTokenBalance += amount;
                rewardRounds[rewardRounds.length - 1].rewardTokens += amount;
                emit RewardDeposit(amount, uint32(rewardRounds.length - 1));

                original_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
            } else {
                TvmCell tvmcell;
                ITONTokenWallet(tokenWallet).transfer{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                    sender_wallet,
                    amount,
                    0,
                    original_gas_to,
                    false,
                    tvmcell
                );
            }
        }
    }

    function revertDeposit(uint64 _deposit_nonce) external override {
        PendingDeposit deposit = deposits[_deposit_nonce];
        address expectedAddr = getUserDataAddress(deposit.user);
        require (expectedAddr == msg.sender, ErrorCodes.NOT_USER_DATA);

        tvm.rawReserve(_reserve(), 2);

        delete deposits[_deposit_nonce];
        emit DepositReverted(deposit.user, deposit.amount);

        TvmCell _empty;
        ITONTokenWallet(tokenWallet).transferToRecipient{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            0, deposit.user, deposit.amount, 0, 0, deposit.send_gas_to, false, _empty
        );
    }

    function finishDeposit(uint64 _deposit_nonce) external override {
        PendingDeposit deposit = deposits[_deposit_nonce];
        address expectedAddr = getUserDataAddress(deposit.user);
        require (expectedAddr == msg.sender, ErrorCodes.NOT_USER_DATA);

        tvm.rawReserve(_reserve(), 2);

        tokenBalance += deposit.amount;

        emit Deposit(deposit.user, deposit.amount);
        delete deposits[_deposit_nonce];

        deposit.send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function withdraw(uint128 amount, address send_gas_to) public onlyActive {
        require (amount > 0, ErrorCodes.ZERO_AMOUNT_INPUT);
        require (msg.value >= Gas.MIN_WITHDRAW_MSG_VALUE, ErrorCodes.VALUE_TOO_LOW);
        tvm.rawReserve(_reserve(), 2);

        updatePoolInfo();

        address userDataAddr = getUserDataAddress(msg.sender);
        // we cant check if user has any balance here, delegate it to UserData
        UserData(userDataAddr).processWithdraw{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            amount, rewardRounds, send_gas_to, user_data_version
        );
    }

    function finishWithdraw(
        address user,
        uint128 withdraw_amount,
        address send_gas_to
    ) public override onlyUserData(user) {
        tvm.rawReserve(_reserve(), 2);

        tokenBalance -= withdraw_amount;

        emit Withdraw(user, withdraw_amount);
        TvmCell tvmcell;
        ITONTokenWallet(tokenWallet).transferToRecipient{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            0, user, withdraw_amount, 0, 0, send_gas_to, false, tvmcell
        );
    }

    function claimReward(address send_gas_to) external onlyActive {
        require (msg.value >= Gas.MIN_CLAIM_REWARD_MSG_VALUE, ErrorCodes.VALUE_TOO_LOW);

        tvm.rawReserve(_reserve(), 2);

        updatePoolInfo();
        address userDataAddr = getUserDataAddress(msg.sender);
        // we cant check if user has any balance here, delegate it to UserData
        UserData(userDataAddr).processClaimReward{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            rewardRounds, send_gas_to, user_data_version
        );
    }

    function finishClaimReward(address user, uint128[] rewards, address send_gas_to) external override onlyUserData(user) {
        tvm.rawReserve(_reserve(), 2);

        uint128 user_token_reward = 0;
        for (uint i = 0; i < rewards.length; i++) {
            RewardRound cur_round = rewardRounds[i];
            if (cur_round.totalReward > 0 && rewards[i] > 0) {
                user_token_reward += math.muldiv(math.muldiv(rewards[i], 1e18, cur_round.totalReward), cur_round.rewardTokens, 1e18);
            }
        }

        user_token_reward = math.min(user_token_reward, rewardTokenBalance);
        rewardTokenBalance -= user_token_reward;

        emit RewardClaimed(user, user_token_reward);

        TvmCell _empty;
        ITONTokenWallet(tokenWallet).transferToRecipient{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            0, user, user_token_reward, 0, 0, send_gas_to, false, _empty
        );
    }


    // user_amount and user_reward_debt should be fetched from UserData at first
    function pendingReward(uint256 user_token_balance, IUserData.RewardRoundData[] user_reward_data) external view responsible returns (uint256) {
        RewardRound[] _reward_rounds = rewardRounds;
        // sync rewards up to this moment
        if (now > lastRewardTime && tokenBalance > 0) {
            // if token balance if empty, no need to update pool info
            uint128 new_reward = (now - lastRewardTime) * rewardPerSecond;
            _reward_rounds[_reward_rounds.length - 1].totalReward += new_reward;
            _reward_rounds[_reward_rounds.length - 1].accRewardPerShare += math.muldiv(new_reward, 1e18, tokenBalance);
        }

        uint256 user_reward_tokens = 0;
        for (uint i = 0; i < _reward_rounds.length; i++) {
            // for old user rounds (which synced already), just get rewards
            if (i < user_reward_data.length - 1) {
                // totalReward in old round cant be empty
                uint256 user_round_share = math.muldiv(user_reward_data[i].reward_balance, 1e18, _reward_rounds[i].totalReward);
                user_reward_tokens += math.muldiv(user_round_share, _reward_rounds[i].rewardTokens, 1e18);
            // sync new user rounds
            } else {
                if (i >= user_reward_data.length) {
                    user_reward_data.push(IUserData.RewardRoundData(0, 0));
                }

                if (_reward_rounds[i].totalReward > 0) {
                    uint256 new_reward = math.muldiv(user_token_balance, _reward_rounds[i].accRewardPerShare, 1e18) - user_reward_data[i].reward_debt;
                    uint256 user_round_reward = user_reward_data[i].reward_balance + new_reward;
                    uint256 user_round_share = math.muldiv(user_round_reward, 1e18, _reward_rounds[i].totalReward);
                    user_reward_tokens += math.muldiv(user_round_share, _reward_rounds[i].rewardTokens, 1e18);
                }
            }
        }
        return { value: 0, flag: MsgFlag.REMAINING_GAS } user_reward_tokens;
    }

    function updatePoolInfo() internal {
        if (now <= lastRewardTime) {
            return;
        }

        if (tokenBalance == 0) {
            lastRewardTime = now;
            return;
        }

        uint128 multiplier = now - lastRewardTime;
        uint128 new_reward = rewardPerSecond * multiplier;
        rewardRounds[rewardRounds.length - 1].totalReward += new_reward;
        lastRewardTime = now;

        rewardRounds[rewardRounds.length - 1].accRewardPerShare += math.muldiv(new_reward, 1e18, tokenBalance);
    }

    function _buildUserDataParams(address user) private view returns (TvmCell) {
        TvmBuilder builder;
        builder.store(user);
        return builder.toCell();
    }

    function _buildInitData(uint8 type_id, TvmCell _initialData) internal view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: Platform,
            varInit: {
                root: address(this),
                platformType: type_id,
                initialData: _initialData,
                platformCode: platform_code
            },
            pubkey: 0,
            code: platform_code
        });
    }

    function deployUserData(address user_data_owner) internal returns (address) {
        TvmBuilder constructor_params;
        constructor_params.store(user_data_version);
        constructor_params.store(user_data_version);
        constructor_params.store(dao_root);

        return new Platform{
            stateInit: _buildInitData(PlatformTypes.UserData, _buildUserDataParams(user_data_owner)),
            value: Gas.DEPLOY_USER_DATA_MIN_VALUE,
            flag: MsgFlag.SENDER_PAYS_FEES
        }(user_data_code, constructor_params.toCell(), user_data_owner);
    }

    function getUserDataAddress(address user) public view responsible returns (address) {
        return { value: 0, flag: MsgFlag.REMAINING_GAS } address(tvm.hash(_buildInitData(
            PlatformTypes.UserData,
            _buildUserDataParams(user)
        )));
    }

    function castVote(uint32 proposal_id, bool support) public view override {
        _castVote(proposal_id, support, '');
    }

    function castVoteWithReason(
        uint32 proposal_id,
        bool support,
        string reason
    ) public view override {
        _castVote(proposal_id, support, reason);
    }

    function _castVote(uint32 proposal_id, bool support, string reason) private view {
        tvm.rawReserve(_reserve(), 2);
        IUserData(getUserDataAddress(msg.sender)).castVote{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(user_data_version, proposal_id, support, reason);
    }

    function tryUnlockVoteTokens(uint32 proposal_id) public view override {
        tvm.rawReserve(_reserve(), 2);
        IUserData(getUserDataAddress(msg.sender)).tryUnlockVoteTokens{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(user_data_version, proposal_id);

    }

    function tryUnlockCastedVotes(uint32[] proposal_ids) public view override {
        tvm.rawReserve(_reserve(), 2);
        IUserData(getUserDataAddress(msg.sender)).tryUnlockCastedVotes{
            value: 0,
            flag: MsgFlag.ALL_NOT_RESERVED
        }(user_data_version, proposal_ids);
    }


    onBounce(TvmSlice slice) external {
        tvm.accept();

        uint32 functionId = slice.decode(uint32);
        // if processing failed - contract was not deployed. Deploy and try again
        if (functionId == tvm.functionId(UserData.processDeposit)) {
            tvm.rawReserve(_reserve(), 2);

            uint64 _deposit_nonce = slice.decode(uint64);
            PendingDeposit deposit = deposits[_deposit_nonce];
            address user_data_addr = deployUserData(deposit.user);
            // try again
            UserData(user_data_addr).processDeposit{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
                _deposit_nonce, deposit.amount, rewardRounds, user_data_version
            );
        }
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) {
            checkDelegate();
        }
        _;
    }

    modifier onlyBridge() {
        require (msg.sender == bridge_event_config, ErrorCodes.NOT_BRIDGE);
        _;
    }

    modifier onlyDaoRoot {
        require(msg.sender == dao_root, ErrorCodes.NOT_DAO_ROOT);
        _;
    }

    modifier onlyRewarder {
        require(msg.sender == rewarder, ErrorCodes.NOT_REWARDER);
        _;
    }

    modifier onlyUserData(address user) {
        address expectedAddr = getUserDataAddress(user);
        require (expectedAddr == msg.sender, ErrorCodes.NOT_USER_DATA);
        _;
    }

    modifier onlyActive() {
        require(active, ErrorCodes.NOT_ACTIVE);
        _;
    }

}
