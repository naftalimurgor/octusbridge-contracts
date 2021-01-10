pragma solidity >= 0.6.0;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import "./event-configuration-contracts/EthereumEventConfiguration.sol";
import "./event-configuration-contracts/TonEventConfiguration.sol";

import "./interfaces/IEvent.sol";
import "./interfaces/IBridge.sol";
import "./interfaces/IEventConfiguration.sol";

import "./utils/KeysOwnable.sol";


contract Bridge is KeysOwnable, IBridge {
    uint static _randomNonce;

    BridgeConfiguration bridgeConfiguration;

    struct EventConfiguration {
        mapping(uint => bool) votes;
        address addr;
        bool status;
        IEventConfiguration.EventType _type;
    }

    mapping(uint => EventConfiguration) eventConfigurations;
    event EventConfigurationCreationVote(uint id, uint relayKey, bool vote);
    event EventConfigurationCreationEnd(uint id, bool active, IEventConfiguration.EventType _type);

    struct EventConfigurationUpdate {
        mapping(uint => bool) votes;
        uint targetID;
        address addr;
        IEventConfiguration.BasicConfigurationInitData basicInitData;
        IEventConfiguration.EthereumEventConfigurationInitData ethereumInitData;
        IEventConfiguration.TonEventConfigurationInitData tonInitData;
    }
    mapping(uint => EventConfigurationUpdate) eventConfigurationsUpdate;
    event EventConfigurationUpdateVote(uint id, uint relayKey, bool vote);
    event EventConfigurationUpdateEnd(uint id, bool active);

    mapping(BridgeConfiguration => mapping(uint => bool)) bridgeConfigurationVotes;
    event BridgeConfigurationUpdateVote(BridgeConfiguration _bridgeConfiguration, uint relayKey, Vote vote);
    event BridgeConfigurationUpdateEnd(BridgeConfiguration _bridgeConfiguration, bool status);

    mapping(BridgeRelay => mapping(uint => bool)) bridgeRelayVotes;
    event BridgeRelaysUpdateVote(BridgeRelay target, uint relayKey, Vote vote);
    event BridgeRelaysUpdateEnd(BridgeRelay target, bool status);

    /*
        @dev Throws an error if bridge currently inactive
    */
    modifier onlyActive() {
        require(bridgeConfiguration.active == true, 12312);
        _;
    }

    /*
        @dev Throws and error is event configuration has less confirmations than required or more rejects than allowed
    */
    modifier onlyActiveConfiguration(uint id) {
        require(eventConfigurations[id].status == true, 16922);
        _;
    }

    /*
        Basic Bridge contract
        @param _relayKeys List of relays public keys
        @param _bridgeConfiguration Initial Bridge configuration
    */
    constructor(
        uint[] _relayKeys,
        BridgeConfiguration _bridgeConfiguration
    ) public {
        require(tvm.pubkey() != 0);
        tvm.accept();

        for (uint i=0; i < _relayKeys.length; i++) {
            _grantOwnership(_relayKeys[i]);
        }

        bridgeConfiguration = _bridgeConfiguration;
        bridgeConfiguration.active = true;
    }

    /*
        Vote for Event configuration (any type).
        @dev Called only by relay. In case msg.pubkey() votes second time - nothing happens.
        @dev Event configuration ID should not exist, revert otherwise
        @param id TON event configuration contract address
        @param addr Address of event configuration contract
        @param _type Type of event configuration (Ethereum or TON)
    */
    function initializeEventConfigurationCreation(
        uint id,
        address addr,
        IEventConfiguration.EventType _type
    ) public onlyActive onlyOwnerKey(msg.pubkey()) {
        require(!eventConfigurations.exists(id), 11971);
        tvm.accept();

        uint key = msg.pubkey();

        EventConfiguration _eventConfiguration;
        _eventConfiguration.addr = addr;
        _eventConfiguration._type = _type;
        _eventConfiguration.votes[key] = true;

        eventConfigurations[id] = _eventConfiguration;

        emit EventConfigurationCreationVote(id, key, true);
    }

    /*
        Vote for specific configuration.
        @dev Event configuration ID should exist, revert otherwise
        @param id Event configuration ID
        @param vote Confirm of reject
    */
    function voteForEventConfigurationCreation(
        uint id,
        bool vote
    ) public onlyActive onlyOwnerKey(msg.pubkey()) {
        require(eventConfigurations.exists(id), 11972);
        tvm.accept();

        EventConfiguration _eventConfiguration = eventConfigurations[id];
        _eventConfiguration.votes[msg.pubkey()] = vote;
        eventConfigurations[id] = _eventConfiguration;

        // Get results results
        (uint[] confirmKeys, uint[] rejectKeys,,) = getEventConfigurationDetails(id);

        // - Check voting results and make updates if necessary
        if (
            // -- Relay voted for confirmation AND enough confirmations received AND configuration not confirmed before
            // -- Enable configuration
            confirmKeys.length >= bridgeConfiguration.eventConfigurationRequiredConfirmations &&
            vote == true &&
            eventConfigurations[id].status == false
        ) {
            eventConfigurations[id].status = true;

            emit EventConfigurationCreationEnd(id, true, eventConfigurations[id]._type);
        } else if (
            // -- Relay voted for reject AND enough rejects received
            // -- Remove configuration
            rejectKeys.length >= bridgeConfiguration.eventConfigurationRequiredRejects &&
            vote == false
        ) {
            emit EventConfigurationCreationEnd(id, false, eventConfigurations[id]._type);

            delete eventConfigurations[id];
        }
    }

    /*
        Get list of confirm and reject keys for specific address. Also get status - confirmed or not.
    */
    function getEventConfigurationDetails(
        uint id
    ) public view returns (
        uint[] confirmKeys,
        uint[] rejectKeys,
        address addr,
        bool status
    ) {
        tvm.accept();

        for ((uint key, bool vote): eventConfigurations[id].votes) {
            if (vote == true) {
                confirmKeys.push(key);
            } else {
                rejectKeys.push(key);
            }
        }

        addr = eventConfigurations[id].addr;
        status = eventConfigurations[id].status;
    }

    /*
        Get list of active event configuration contracts
        @returns eventConfigurations List of active event configuration contracts
    */
    function getActiveEventConfigurations() public view returns (
        uint[] ids
    ) {
        tvm.accept();

        for ((uint id, EventConfiguration configuration): eventConfigurations) {
            if (configuration.status) {
                ids.push(id);
            }
        }
    }

    /*
        Confirm Ethereum event instance.
        @dev Called only by relay
        @param eventInitData Ethereum event init data
        @param configurationID Ethereum Event configuration ID
    */
    function confirmEthereumEvent(
        IEvent.EthereumEventInitData eventInitData,
        uint configurationID
    ) public view onlyActive onlyOwnerKey(msg.pubkey()) onlyActiveConfiguration(configurationID) {
        tvm.accept();

        EthereumEventConfiguration(eventConfigurations[configurationID].addr).confirmEvent{value: 1 ton}(
            eventInitData,
            msg.pubkey()
        );
    }

    /*
        Reject Ethereum event instance.
        @dev Called only by relay. Only reject already existing EthereumEvent contract, not create it.
        @param eventInitData Ethereum event init data
        @param configurationID Ethereum Event configuration ID
    */
    function rejectEthereumEvent(
        IEvent.EthereumEventInitData eventInitData,
        uint configurationID
    ) public view onlyActive onlyOwnerKey(msg.pubkey()) onlyActiveConfiguration(configurationID) {
        tvm.accept();

        EthereumEventConfiguration(eventConfigurations[configurationID].addr).rejectEvent{value: 1 ton}(
            eventInitData,
            msg.pubkey()
        );
    }

    /*
        Confirm TON event instance.
        @dev Called only by relay
        @param eventInitData Event contract init data
        @param eventDataSignature Relay's signature of the Ethereum callback
        @param configurationID Ethereum Event configuration ID
    */
    function confirmTonEvent(
        IEvent.TonEventInitData eventInitData,
        bytes eventDataSignature,
        uint configurationID
    ) public view onlyActive onlyOwnerKey(msg.pubkey()) onlyActiveConfiguration(configurationID) {
        tvm.accept();

        TonEventConfiguration(eventConfigurations[configurationID].addr).confirmEvent{value: 1 ton}(
            eventInitData,
            eventDataSignature,
            msg.pubkey()
        );
    }

    /*
        Reject TON event instance.
        @dev Called only by relay. Only reject already existing TonEvent contract, not create it.
        @param eventInitData Event contract init data
        @param eventDataSignature Relay's signature of the Ethereum callback
        @param configurationID Ethereum Event configuration ID
    */
    function rejectTonEvent(
        IEvent.TonEventInitData eventInitData,
        uint configurationID
    ) public view onlyActive onlyOwnerKey(msg.pubkey()) onlyActiveConfiguration(configurationID) {
        tvm.accept();

        TonEventConfiguration(eventConfigurations[configurationID].addr).rejectEvent{value: 1 ton}(
            eventInitData,
            msg.pubkey()
        );
    }

    /*
        Convert Vote structure to the decision of voter.
        @dev Since signature needs to mirror voting in Ethereum bridge
        It doesn't need if relay reject the voting
        His vote just won't be passed to Ethereum, if voting reaches enough confirmations
        @returns bool Yes or no
    */
    function getVotingDirection(Vote _vote) public pure returns(bool vote) {
        if (_vote.signature.length == 0) {
            vote = false;
        } else {
            vote = true;
        }
    }

    /*
        Vote for Bridge configuration update
        @dev Can be called only by relay
        @param _bridgeConfiguration New bridge configuration
        @param _vote Vote structure. Signature and payload are empty for reject.
    */
    function updateBridgeConfiguration(
        BridgeConfiguration _bridgeConfiguration,
        Vote _vote
    ) public onlyOwnerKey(msg.pubkey()) {
        // TODO: discuss replay protection in TON and Ethereum
        tvm.accept();

        emit BridgeConfigurationUpdateVote(_bridgeConfiguration, msg.pubkey(), _vote);

        bool vote = getVotingDirection(_vote);

        bridgeConfigurationVotes[_bridgeConfiguration][msg.pubkey()] = vote;

        // Check the results
        (uint[] confirmKeys, uint[] rejectKeys) = getBridgeConfigurationVotes(_bridgeConfiguration);

        // - If enough confirmations received - update configuration and remove voting
        if (confirmKeys.length == bridgeConfiguration.bridgeConfigurationUpdateRequiredConfirmations) {
            bridgeConfiguration = _bridgeConfiguration;
            _removeBridgeConfigurationVoting(_bridgeConfiguration);

            emit BridgeConfigurationUpdateEnd(_bridgeConfiguration, true);
        }

        // - If enough rejects received - remove voting
        if (rejectKeys.length == bridgeConfiguration.bridgeConfigurationUpdateRequiredRejects) {
            _removeBridgeConfigurationVoting(_bridgeConfiguration);

            emit BridgeConfigurationUpdateEnd(_bridgeConfiguration, false);
        }
    }

    /*
        Garbage collector for update configuration voting
        @dev Called each time voting ends and remove it details from the storage
    */
    function _removeBridgeConfigurationVoting(
        BridgeConfiguration _bridgeConfiguration
    ) internal {
        delete bridgeConfigurationVotes[_bridgeConfiguration];
    }

    /*
        Get list of votes for bridge configuration update ID
        @param _bridgeConfiguration Bridge configuration
        @returns confirmKeys List of keys who confirmed the update
        @returns rejectKeys List of keys who rejected the update
    */
    function getBridgeConfigurationVotes(
        BridgeConfiguration _bridgeConfiguration
    ) public view returns(
        uint[] confirmKeys,
        uint[] rejectKeys
    ) {
        for ((uint key, bool vote): bridgeConfigurationVotes[_bridgeConfiguration]) {
            if (vote == true) {
                confirmKeys.push(key);
            } else {
                rejectKeys.push(key);
            }
        }
    }


    /*
        Initialize event configuration update. Allows to update event configuration contract address.
        And make a call to the event configuration contract, which updates any data.
        @dev Basic init data and init data would be send to event configuration anyway
        @dev If you don't want to change them - just copy already existing and use them
        @dev If you want to update Ethereum event configuration, fill the tonInitData with dummy data,
        it won't be used anyway. The same works for TON configuration update.
        @param id ID of the update, should not be used before
        @param update Details of the update
    */
    function initializeUpdateEventConfiguration(
        uint id,
        uint targetID,
        address addr,
        IEventConfiguration.BasicConfigurationInitData basicInitData,
        IEventConfiguration.EthereumEventConfigurationInitData ethereumInitData,
        IEventConfiguration.TonEventConfigurationInitData tonInitData
    ) public onlyActive onlyOwnerKey(msg.pubkey()) {
        require(!eventConfigurationsUpdate.exists(id), 17777);
        require(eventConfigurations.exists(targetID), 17778);
        tvm.accept();

        uint key = msg.pubkey();

        EventConfigurationUpdate update;
        update.targetID = targetID;
        update.addr = addr;
        update.basicInitData = basicInitData;
        update.ethereumInitData = ethereumInitData;
        update.tonInitData = tonInitData;
        update.votes[key] = true;

        eventConfigurationsUpdate[id] = update;

        emit EventConfigurationCreationVote(id, key, true);
    }

    /*
        Vote for already existing event configuration update.
        @dev If voting finished - update an address from the update data. And send new (basicInitData, initData)
        to the event configuration contract, depending of it's type
        @param id Update ID
        @param vote Confirm / reject
    */
    function voteForUpdateEventConfiguration(
        uint id,
        bool vote
    ) public onlyActive onlyOwnerKey(msg.pubkey()) {
        tvm.accept();

        uint key = msg.pubkey();

        EventConfigurationUpdate update = eventConfigurationsUpdate[id];
        update.votes[key] = vote;
        eventConfigurationsUpdate[id] = update;

        emit EventConfigurationUpdateVote(id, key, vote);

        // Check the results
        (uint[] confirmKeys, uint[] rejectKeys,,,,,) = getUpdateEventConfigurationDetails(id);

        // - Enough confirmations received, update event configuration
        if (confirmKeys.length == bridgeConfiguration.eventConfigurationRequiredConfirmations) {
            // -- Update event configuration address
            eventConfigurations[update.targetID].addr = update.addr;

            if (eventConfigurations[update.targetID]._type == IEventConfiguration.EventType.Ethereum) {
                EthereumEventConfiguration(eventConfigurations[update.targetID].addr).updateInitData{value: 1 ton}(
                    update.basicInitData,
                    update.ethereumInitData
                );
            } else {
                TonEventConfiguration(eventConfigurations[update.targetID].addr).updateInitData{value: 1 ton}(
                    update.basicInitData,
                    update.tonInitData
                );
            }

            emit EventConfigurationUpdateEnd(id, true);

            _removeUpdateEventConfiguration(id);
        }

        if (rejectKeys.length == bridgeConfiguration.eventConfigurationRequiredRejects) {
            emit EventConfigurationUpdateEnd(id, false);
            _removeUpdateEventConfiguration(id);
        }
    }

    /*
        Get details for specific configuration update
        @param id Update event configuration ID
        @returns confirmKeys List of keys confirmed update
        @returns rejectKeys List of keys rejected update
    */
    function getUpdateEventConfigurationDetails(
        uint id
    ) public view returns(
        uint[] confirmKeys,
        uint[] rejectKeys,
        uint targetID,
        address addr,
        IEventConfiguration.BasicConfigurationInitData basicInitData,
        IEventConfiguration.EthereumEventConfigurationInitData ethereumInitData,
        IEventConfiguration.TonEventConfigurationInitData tonInitData
    ) {
        tvm.accept();

        for ((uint key, bool vote): eventConfigurationsUpdate[id].votes) {
            if (vote == true) {
                confirmKeys.push(key);
            } else {
               rejectKeys.push(key);
            }
        }

        basicInitData = eventConfigurationsUpdate[id].basicInitData;
        ethereumInitData = eventConfigurationsUpdate[id].ethereumInitData;
        tonInitData = eventConfigurationsUpdate[id].tonInitData;
        targetID = eventConfigurationsUpdate[id].targetID;
        addr = eventConfigurationsUpdate[id].addr;
    }

    /*
        Garbage collector for event configuration update
        @dev removes the update details
    */
    function _removeUpdateEventConfiguration(uint id) internal {
        delete eventConfigurationsUpdate[id];
    }


    /*
        Vote for Bridge relays update
        @dev Called only by relay
        @param target Target relay
        @param _vote Vote structure. Signature and payload are empty for reject.
    */
    function updateBridgeRelays(
        BridgeRelay target,
        Vote _vote
    ) public onlyOwnerKey(msg.pubkey()) {
        // TODO: discuss usage of onlyActive
        tvm.accept();

        emit BridgeRelaysUpdateVote(target, msg.pubkey(), _vote);

        bool vote = getVotingDirection(_vote);

        bridgeRelayVotes[target][msg.pubkey()] = vote;

        // Check the results
        (uint[] confirmKeys, uint[] rejectKeys) = getBridgeRelayVotes(target);

        // - If enough confirmations received - update configuration and remove voting
        if (confirmKeys.length == bridgeConfiguration.bridgeRelayUpdateRequiredConfirmations) {
            if (target.action) {
                _grantOwnership(target.key);
            } else {
                _removeOwnership(target.key);
            }

            _removeBridgeRelayVoting(target);

            emit BridgeRelaysUpdateEnd(target, true);
        }

        // - If enough rejects received - remove voting
        if (rejectKeys.length == bridgeConfiguration.bridgeRelayUpdateRequiredRejects) {
            _removeBridgeRelayVoting(target);

            emit BridgeRelaysUpdateEnd(target, false);
        }
    }

    /*
        Get list of keys who confirmed and rejected specific voting
    */
    function getBridgeRelayVotes(
        BridgeRelay target
    ) public view returns(
        uint[] confirmKeys,
        uint[] rejectKeys
    ) {
        for ((uint key, bool vote): bridgeRelayVotes[target]) {
            if (vote == true) {
                confirmKeys.push(key);
            } else {
                rejectKeys.push(key);
            }
        }
    }


    /*
        Garbage collector for update relay
        @dev Called each time voting ends and remove it's details from the storage
    */
    function _removeBridgeRelayVoting(
        BridgeRelay target
    ) internal {
        delete bridgeRelayVotes[target];
    }

    /*
        Get Bridge details.
        @returns _bridgeConfiguration Structure with Bridge configuration details
    */
    function getDetails() public view returns (
        BridgeConfiguration _bridgeConfiguration
    ) {
        return (
            bridgeConfiguration
        );
    }

}
