// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./interfaces/IBridge.sol";
import "./libraries/ECDSA.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "hardhat/console.sol";

/**
    @title Ethereum Bridge contract.
    @dev Stores relays for each round
    @dev Controlled by DAO
    @dev Implements handy functions to be used in bridge integration contracts
**/
contract Bridge is OwnableUpgradeable, IBridge {
    using ECDSA for bytes32;

    mapping (uint32 => mapping(address => bool)) public roundRelays;
    mapping (uint32 => uint32) public roundRequiredSignatures;
    BridgeConfiguration public configuration;
    uint public lastRound;

    /**
        @param admin Bridge admin
        @param relays Set of relays for round 0
    **/
    function initialize(
        address admin,
        BridgeConfiguration calldata _configuration,
        address[] calldata relays
    ) external initializer {
        __Ownable_init();
        transferOwnership(admin);

        _setConfiguration(_configuration);

        _setRoundRelays(0, relays);
        lastRound = 0;
    }

    /*
        @notice Internal function for setting bridge configuration
        @param _configuration Bridge configuration
    */
    function _setConfiguration(
        BridgeConfiguration memory _configuration
    ) internal {
        configuration = _configuration;

        emit ConfigurationUpdate(_configuration);
    }

    /*
        @notice Internal function for updating up relays for specific round
        @param round Round id
        @param relays Array of relay addresses
    */
    function _setRoundRelays(
        uint32 round,
        address[] memory relays
    ) internal {
        roundRequiredSignatures[round] = uint32(relays.length * 2 / 3) + 1;

        for (uint i=0; i<relays.length; i++) {
            roundRelays[round][relays[i]] = true;

            emit RoundRelayGranted(round, relays[i]);
        }
    }

    /*
        @notice Answers if specific address was relay in specific round
        @param round Round id
        @param candidate Address to check
    */
    function isRelay(
        uint32 round,
        address candidate
    ) override public view returns (bool) {
        return roundRelays[round][candidate];
    }

    /*
        @notice Verify there is enough relay signatures
        @dev Required amount of signatures is (2/3 * relays at round) + 1
        @dev Signatures should be sorted by the ascending signers, so it's cheaper to detect duplicates
        // TODO: discuss min amount of required signatures
        @param round Round id
        @param payload Bytes encoded payload
        @param signatures Payload signatures
        @returns All checks are passed or not
    */
    function verifyRelaySignatures(
        uint32 round,
        bytes memory payload,
        bytes[] memory signatures
    ) override public view returns (bool) {
        require(round <= lastRound, "Bridge: too high round");

        address lastSigner = address(0);
        uint32 count = 0;

        uint32 requiredSignatures = roundRequiredSignatures[round];

        for (uint i=0; i<signatures.length; i++) {
            address signer = recoverSignature(payload, signatures[i]);

            require(signer > lastSigner, "Bridge: signatures sequence wrong");
            lastSigner = signer;

            if (isRelay(round, signer)) {
                count++;
            }
        }

        return count >= requiredSignatures;
    }

    // TODO: discuss removing relays
    /*
        @notice Recover signer from the payload and signature
        @param payload Payload
        @param signature Signature
    */
    function recoverSignature(
        bytes memory payload,
        bytes memory signature
    ) public pure returns (address signer) {
        signer = keccak256(payload)
            .toBytesPrefixed()
            .recover(signature);
    }

    /*
        @notice Grant relay permission for addresses at specific round
        @param round Round number on which to set relays
        @param signatures Payload signatures
    */
    function setRoundRelays(
        uint32 round,
        address[] calldata relays
    ) override external onlyOwner {
        require(round == lastRound + 1, "Bridge: wrong round");

        lastRound++;

        _setRoundRelays(round, relays);
    }

    /*
        @notice Update bridge configuration
        @dev Only owner
        @param _configuration New bridge configuration
    */
    function setConfiguration(
        BridgeConfiguration calldata _configuration
    ) override external onlyOwner {
        _setConfiguration(_configuration);
    }
}
