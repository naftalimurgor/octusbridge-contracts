pragma ton-solidity >= 0.39.0;
pragma AbiHeader time;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import "./../interfaces/ITokenRootAlienSolanaEverscale.sol";

import '@broxus/contracts/contracts/libraries/MsgFlag.sol';
import "ton-eth-bridge-token-contracts/contracts/TokenRootUpgradeable.sol";


contract TokenRootAlienSolanaEverscale is TokenRootUpgradeable, ITokenRootAlienSolanaEverscale {
    uint256 static base_token_;

    constructor(
        address initialSupplyTo,
        uint128 initialSupply,
        uint128 deployWalletValue,
        bool mintDisabled,
        bool burnByRootDisabled,
        bool burnPaused,
        address remainingGasTo
    ) public TokenRootUpgradeable(
        initialSupplyTo,
        initialSupply,
        deployWalletValue,
        mintDisabled,
        burnByRootDisabled,
        burnPaused,
        remainingGasTo
    ) {}

    function meta() external override responsible returns (
        uint256 base_token,
        string name,
        string symbol,
        uint8 decimals
    ) {
        return{value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS}(
            base_token_,
            name_,
            symbol_,
            decimals_
        );
    }
}