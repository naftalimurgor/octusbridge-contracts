pragma ton-solidity >= 0.39.0;
pragma AbiHeader pubkey;
//pragma AbiHeader expire;

import "./StakingUpgradable.sol";
import "../../bridge/interfaces/event-configuration-contracts/ITonEventConfiguration.sol";
import "../../bridge/interfaces/IProxy.sol";


abstract contract StakingPoolRelay is StakingPoolUpgradable, IProxy {
    function linkRelayAccounts(uint256 ton_pubkey, uint160 eth_address) external view onlyActive {
        require (msg.value >= relay_config.relayInitialDeposit, ErrorCodes.VALUE_TOO_LOW);
        require (!base_details.emergency, ErrorCodes.EMERGENCY);

        tvm.rawReserve(_reserve(), 2);

        uint128 user_data_value = msg.value / 2;

        address user_data = getUserDataAddress(msg.sender);
        IUserData(user_data).processLinkRelayAccounts{ value: user_data_value }(
            ton_pubkey, eth_address, false, user_data_version
        );
    }

    function broxusBridgeCallback(
        IEthereumEvent.EthereumEventInitData eventData,
        address gasBackAddress
    ) external override onlyEthTonConfig {
        require (msg.value >= Gas.MIN_CALL_MSG_VALUE, ErrorCodes.VALUE_TOO_LOW);
        tvm.rawReserve(_reserve(), 2);

        (uint160 eth_addr, int8 wk_id, uint256 ton_addr_body) = eventData.voteData.eventData.toSlice().decode(uint160, int8, uint256);
        address ton_staker_addr = address.makeAddrStd(wk_id, ton_addr_body);
        confirmEthAccount(ton_staker_addr, eth_addr, gasBackAddress);
    }

    function confirmEthAccount(address staker_addr, uint160 eth_address, address send_gas_to) internal {
        address user_data = getUserDataAddress(staker_addr);
        IUserData(user_data).processConfirmEthAccount{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }(eth_address, send_gas_to);
    }

    function slashRelay(address relay_staker_addr, address send_gas_to) external onlyDaoRoot {
        require (msg.value >= Gas.MIN_CALL_MSG_VALUE, ErrorCodes.VALUE_TOO_LOW);

        tvm.rawReserve(_reserve(), 2);

        updatePoolInfo();
        _upgradeUserData(relay_staker_addr, Gas.USER_DATA_UPGRADE_VALUE, send_gas_to);

        address user_data = getUserDataAddress(relay_staker_addr);
        IUserData(user_data).slash{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }(base_details.rewardRounds, send_gas_to);
    }

    function _syncUserRewardData(
        uint128[] user_rewards,
        uint128[] user_debts,
        uint128 ban_token_balance
    ) private view returns (uint128[]) {
        for (uint i = user_rewards.length - 1; i < base_details.rewardRounds.length; i++) {
            if (i >= user_rewards.length) {
                user_rewards.push(0);
                user_debts.push(0);
            }
            user_rewards[i] += uint128(((ban_token_balance * base_details.rewardRounds[i].accRewardPerShare) / SCALING_FACTOR) - user_debts[i]);
        }
        return user_rewards;
    }

    function confirmSlash(
        address user,
        uint128[] user_rewards,
        uint128[] user_debts,
        uint128 ban_token_balance,
        address send_gas_to
    ) external override onlyUserData(user) {
        tvm.rawReserve(_reserve(), 2);

        updatePoolInfo();
        // sync user rewards up to this moment
        uint128[] user_rewards_synced = _syncUserRewardData(user_rewards, user_debts, ban_token_balance);

        uint128 _tokens_added_to_reward = 0;
        for (uint i = 0; i < user_rewards_synced.length; i++) {
            uint256 _share = (user_rewards_synced[i] * SCALING_FACTOR) / base_details.rewardRounds[i].totalReward;
            uint128 _ban_tokens = uint128((_share * base_details.rewardRounds[i].rewardTokens) / SCALING_FACTOR);
            _tokens_added_to_reward += _ban_tokens;
            base_details.rewardRounds[i].totalReward -= user_rewards_synced[i];
        }
        _tokens_added_to_reward += ban_token_balance;
        // transfer all staked tokens to current round reward balance
        base_details.rewardRounds[base_details.rewardRounds.length - 1].rewardTokens += _tokens_added_to_reward;
        base_details.tokenBalance -= ban_token_balance;
        base_details.rewardTokenBalance += ban_token_balance;

        emit RelaySlashed(user, _tokens_added_to_reward);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function createOriginRelayRound(
        address[] staker_addrs,
        uint256[] ton_pubkeys,
        uint160[] eth_addrs,
        uint128[] staked_tokens,
        uint128 ton_deposit,
        address send_gas_to
    ) external onlyAdmin {
        require (staker_addrs.length <= RELAY_PACK_SIZE, ErrorCodes.BAD_INPUT_ARRAYS);
        require (msg.value >= Gas.MIN_CALL_MSG_VALUE + ton_deposit * staker_addrs.length, ErrorCodes.VALUE_TOO_LOW);
        require (round_details.currentRelayRound == 0 && round_details.currentRelayRoundStartTime == 0, ErrorCodes.ORIGIN_ROUND_ALREADY_INITIALIZED);
        require (ton_deposit > Gas.DEPLOY_USER_DATA_MIN_VALUE + 0.2 ton, ErrorCodes.VALUE_TOO_LOW);
        bool correct_len = staker_addrs.length == ton_pubkeys.length;
        bool correct_len_1 = ton_pubkeys.length == eth_addrs.length;
        bool correct_len_2 = eth_addrs.length == staked_tokens.length;
        require (correct_len && correct_len_1 && correct_len_2, ErrorCodes.BAD_INPUT_ARRAYS);
        tvm.rawReserve(_reserve(), 2);

        for (uint i = 0; i < staker_addrs.length; i++) {
            // manually confirm all relays
            address user_data_addr = deployUserData(staker_addrs[i]);
            IUserData(user_data_addr).processLinkRelayAccounts{ value: ton_deposit - Gas.DEPLOY_USER_DATA_MIN_VALUE }(
                ton_pubkeys[i], eth_addrs[i], true, user_data_version
            );
        }

        // we have 0 relay rounds at the moment
        address empty = address.makeAddrNone();
        address relay_round = deployRelayRound(0, false, 1, empty, empty, MsgFlag.SENDER_PAYS_FEES);
        IRelayRound(relay_round).setRelays{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }(
            ton_pubkeys, eth_addrs, staker_addrs, staked_tokens
        );
    }

    function processBecomeRelayNextRound(address user) external view override onlyActive onlyUserData(user) {
        require (round_details.currentElectionStartTime != 0, ErrorCodes.ELECTION_NOT_STARTED);

        tvm.rawReserve(_reserve(), 2);

        uint32 lock_time = relay_config.electionTime + relay_config.relayLockTime;

        IUserData(msg.sender).processBecomeRelayNextRound2{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            round_details.currentRelayRound + 1, lock_time, relay_config.minRelayDeposit, user_data_version, election_version
        );
    }

    function processGetRewardForRelayRound(address user, uint32 round_num) external override onlyActive onlyUserData(user) {
        tvm.rawReserve(_reserve(), 2);
        updatePoolInfo();

        IUserData(msg.sender).processGetRewardForRelayRound2{value: 0, flag: MsgFlag.ALL_NOT_RESERVED}(
            base_details.rewardRounds, round_num, user_data_version, relay_round_version
        );
    }

    function startElectionOnNewRound() external onlyActive {
        require (now >= (round_details.currentRelayRoundStartTime + relay_config.timeBeforeElection), ErrorCodes.TOO_EARLY_FOR_ELECTION);
        require (round_details.currentElectionStartTime == 0, ErrorCodes.ELECTION_ALREADY_STARTED);
        require (round_details.currentRelayRoundStartTime > 0, ErrorCodes.ORIGIN_ROUND_NOT_INITIALIZED);
        require (!base_details.emergency, ErrorCodes.EMERGENCY);

        // if currentElectionEnded == true, that means we are in a gap between election end and new round initialization
        require (round_details.currentElectionEnded == false, ErrorCodes.ELECTION_ALREADY_STARTED);
        // flags for election start are set on callback, so that ban duplicate calls to prevent contract gas leak
        require (now >= lastExtCall + EXTERNAL_CALL_INTERVAL, ErrorCodes.DUPLICATE_CALL);

        require (address(this).balance >= Gas.MIN_CALL_MSG_VALUE + Gas.ROOT_INITIAL_BALANCE, ErrorCodes.LOW_BALANCE);

        tvm.accept();

        lastExtCall = now;
        deployElection(round_details.currentRelayRound + 1, address(this));
    }

    function endElection() external onlyActive {
        require (!base_details.emergency, ErrorCodes.EMERGENCY);
        require (round_details.currentElectionStartTime != 0, ErrorCodes.ELECTION_NOT_STARTED);
        require (now >= (round_details.currentElectionStartTime + relay_config.electionTime), ErrorCodes.CANT_END_ELECTION);
        // flags for election end are set on callback, so that ban duplicate calls to prevent contract gas leak
        require (now >= lastExtCall + EXTERNAL_CALL_INTERVAL, ErrorCodes.DUPLICATE_CALL);

        uint128 required_gas = Gas.MIN_CALL_MSG_VALUE + _relaysPacksCount() * Gas.MIN_SEND_RELAYS_MSG_VALUE;
        uint128 min_balance = required_gas + Gas.ROOT_INITIAL_BALANCE;
        require (address(this).balance > min_balance, ErrorCodes.LOW_BALANCE);

        tvm.accept();

        lastExtCall = now;

        address election_addr = getElectionAddress(round_details.currentRelayRound + 1);
        IElection(election_addr).finish{value: required_gas}(election_version);
    }

    function onElectionStarted(uint32 round_num, address send_gas_to) external override onlyElection(round_num) {
        tvm.rawReserve(_reserve(), 2);

        round_details.currentElectionStartTime = now;
        emit ElectionStarted(round_num, now, now + relay_config.electionTime, msg.sender);
        send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
    }

    function onElectionEnded(
        uint32 round_num,
        uint32 relay_requests_count
    ) external override onlyElection(round_num) {
        tvm.rawReserve(_reserve(), 2);

        bool min_relays_ok = relay_requests_count >= relay_config.minRelaysCount;

        round_details.currentElectionStartTime = 0;
        round_details.currentElectionEnded = true;

        emit ElectionEnded(round_num, relay_requests_count, min_relays_ok);

        uint8 packs_num = _relaysPacksCount();
        address election = msg.sender;
        address prev_relay_round = getRelayRoundAddress(round_num - 1);
        deployRelayRound(round_num, !min_relays_ok, packs_num, election, prev_relay_round, MsgFlag.ALL_NOT_RESERVED);
    }

    function _relaysPacksCount() private view returns (uint8) {
        uint8 packs_count = uint8(relay_config.relaysCount / RELAY_PACK_SIZE);
        uint8 modulo = relay_config.relaysCount % RELAY_PACK_SIZE > 0 ? 1 : 0;
        return packs_count + modulo;
    }

    function onRelayRoundDeployed(
        uint32 round_num,
        bool duplicate
    ) external override onlyRelayRound(round_num) {
        tvm.rawReserve(_reserve(), 2);

        if (round_num == 0) {
            // this is an origin round deployment
            return;
        }

        address cur_round_addr = msg.sender;
        if (duplicate) {
            // get relays from previous relay round
            address relay_round_addr = getRelayRoundAddress(round_num - 1);
            // send some value to cover possible storage fees before sending msgs
            relay_round_addr.transfer(Gas.RELAY_ROUND_INITIAL_BALANCE, false);
            for (uint i = 0; i < _relaysPacksCount(); i++) {
                // last pack could be smaller then other ones
                if (i == _relaysPacksCount() - 1 && relay_config.relaysCount % RELAY_PACK_SIZE > 0) {
                    IRelayRound(relay_round_addr).sendRelaysToRelayRound{value: Gas.MIN_SEND_RELAYS_MSG_VALUE}(
                        cur_round_addr, relay_config.relaysCount % RELAY_PACK_SIZE
                    );
                } else {
                    IRelayRound(relay_round_addr).sendRelaysToRelayRound{value: Gas.MIN_SEND_RELAYS_MSG_VALUE}(
                        cur_round_addr, RELAY_PACK_SIZE
                    );
                }
            }
        } else {
            // get relays from current election
            address election_addr = getElectionAddress(round_num);
            election_addr.transfer(Gas.ELECTION_INITIAL_BALANCE, false);
            for (uint i = 0; i < _relaysPacksCount(); i++) {
                // last pack could be smaller then other ones
                if (i == _relaysPacksCount() - 1 && relay_config.relaysCount % RELAY_PACK_SIZE > 0) {
                    IElection(election_addr).sendRelaysToRelayRound{value: Gas.MIN_SEND_RELAYS_MSG_VALUE}(
                        cur_round_addr, relay_config.relaysCount % RELAY_PACK_SIZE
                    );
                } else {
                    IElection(election_addr).sendRelaysToRelayRound{value: Gas.MIN_SEND_RELAYS_MSG_VALUE}(
                        cur_round_addr, RELAY_PACK_SIZE
                    );
                }
            }
        }
    }

    function onRelayRoundInitialized(
        uint32 round_num,
        uint32 round_start_time,
        uint32 round_end_time,
        uint32 relays_count,
        uint128 round_reward,
        bool duplicate,
        uint160[] eth_keys
    ) external override onlyRelayRound(round_num) {
        // this method is called with remaining balance from setRelays call of RelayRound which is lower than we need
        // so that we manually increase reservation
        // we know that balance of this contract is enough, because we checked that on 'endElection' call which triggers this action
        tvm.rawReserve(_reserve() - tonEventDeployValue, 2);

        round_details.currentElectionEnded = false;
        round_details.currentRelayRound = round_num;
        round_details.currentRelayRoundStartTime = round_start_time;
        base_details.rewardRounds[base_details.rewardRounds.length - 1].totalReward += round_reward;

        if (round_num > 0) {
            // regular case
            round_details.prevRelayRoundEndTime = round_details.currentRelayRoundEndTime;
            // we started new round too late!
            if (round_details.prevRelayRoundEndTime <= round_details.currentRelayRoundStartTime) {
                // extend prev round as if current round was deployed in time with minimum gap
                round_details.prevRelayRoundEndTime = round_details.currentRelayRoundStartTime + relay_config.minRoundGapTime;
            }
            // gap before new round cant be too low (for case when round was deployed late, but before prev round end)
            if (round_details.prevRelayRoundEndTime - round_details.currentRelayRoundStartTime < relay_config.minRoundGapTime) {
                round_details.prevRelayRoundEndTime = round_details.currentRelayRoundStartTime + relay_config.minRoundGapTime;
            }

            TvmBuilder event_builder;
            event_builder.store(round_num); // 32
            event_builder.store(eth_keys); // ref
            event_builder.store(round_end_time);
            ITonEvent.TonEventVoteData event_data = ITonEvent.TonEventVoteData(tx.timestamp, now, event_builder.toCell());
            ITonEventConfiguration(base_details.bridge_event_config_ton_eth).deployEvent{value: tonEventDeployValue}(event_data);
        }
        round_details.currentRelayRoundEndTime = round_end_time;

        address election_addr = getElectionAddress(round_num);
        IElection(election_addr).destroy{value: Gas.DESTROY_MSG_VALUE}();
        if (round_num >= 3) {
            address old_relay_round = getRelayRoundAddress(round_num - 3);
            IRelayRound(old_relay_round).destroy{value: Gas.DESTROY_MSG_VALUE}();
        }
        emit RelayRoundInitialized(round_num, round_start_time, round_end_time, msg.sender, relays_count, duplicate);
    }

    function deployElection(uint32 round_num, address send_gas_to) private returns (address) {
        require(round_num > round_details.currentRelayRound, ErrorCodes.INVALID_ELECTION_ROUND);

        TvmBuilder constructor_params;
        constructor_params.store(election_version);
        constructor_params.store(election_version);

        return new Platform{
            stateInit: _buildInitData(PlatformTypes.Election, _buildElectionParams(round_num)),
            value: Gas.DEPLOY_ELECTION_MIN_VALUE
        }(election_code, constructor_params.toCell(), send_gas_to);
    }

    function deployRelayRound(
        uint32 round_num,
        bool duplicate,
        uint8 packs_num,
        address election_addr,
        address prev_relay_round_addr,
        uint16 msg_flag
    ) private returns (address) {
        TvmBuilder constructor_params;
        constructor_params.store(relay_round_version);
        constructor_params.store(relay_round_version);
        constructor_params.store(relay_config.relayRoundTime);
        constructor_params.store(uint32(base_details.rewardRounds.length - 1));
        constructor_params.store(rewardPerSecond);
        constructor_params.store(duplicate);
        constructor_params.store(packs_num);
        constructor_params.store(election_addr);
        constructor_params.store(prev_relay_round_addr);

        return new Platform{
            stateInit: _buildInitData(PlatformTypes.RelayRound, _buildRelayRoundParams(round_num)),
            value: Gas.DEPLOY_RELAY_ROUND_MIN_VALUE,
            flag: msg_flag
        }(relay_round_code, constructor_params.toCell(), address(this));
    }

    modifier onlyElection(uint32 round_num) {
        address expectedAddr = getElectionAddress(round_num);
        require (expectedAddr == msg.sender, ErrorCodes.NOT_ELECTION);
        _;
    }

    modifier onlyRelayRound(uint32 round_num) {
        address expectedAddr = getRelayRoundAddress(round_num);
        require (expectedAddr == msg.sender, ErrorCodes.NOT_RELAY_ROUND);
        _;
    }

}
