// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.2;


import "./../interfaces/multivault/IMultiVault.sol";
import "./../interfaces/IEverscale.sol";


library MultiVaultLibrary {
    function decodeNativeWithdrawalEventData(
        bytes memory eventData
    ) internal pure returns (IMultiVault.NativeWithdrawalParams memory) {
        (
            int8 native_wid,
            uint256 native_addr,

            string memory name,
            string memory symbol,
            uint8 decimals,

            uint128 amount,
            uint160 recipient,
            uint256 chainId
        ) = abi.decode(
            eventData,
            (
                int8, uint256,
                string, string, uint8,
                uint128, uint160, uint256
            )
        );

        return IMultiVault.NativeWithdrawalParams({
            native: IEverscale.EverscaleAddress(native_wid, native_addr),
            meta: IMultiVault.TokenMeta(name, symbol, decimals),
            amount: amount,
            recipient: address(recipient),
            chainId: chainId
        });
    }

    function decodeAlienWithdrawalEventData(
        bytes memory eventData
    ) internal pure returns (IMultiVault.AlienWithdrawalParams memory) {
        (
            uint160 token,
            uint128 amount,
            uint160 recipient,
            uint256 chainId
        ) = abi.decode(
            eventData,
            (uint160, uint128, uint160, uint256)
        );

        return IMultiVault.AlienWithdrawalParams({
            token: address(token),
            amount: uint256(amount),
            recipient: address(recipient),
            chainId: chainId
        });
    }

    /// @notice Calculates the CREATE2 address for token, based on the Everscale sig
    /// @param native_wid Everscale token workchain ID
    /// @param native_addr Everscale token address body
    /// @return token Token address
    function getNativeToken(
        int8 native_wid,
        uint256 native_addr
    ) internal view returns (address token) {
        token = address(uint160(uint(keccak256(abi.encodePacked(
            hex'ff',
            address(this),
            keccak256(abi.encodePacked(native_wid, native_addr)),
            hex'f906ad1ce83ab732d793f0a6616e037f193f2bb624880b305bf4af30b8ab228e' // MultiVaultToken init code hash
        )))));
    }
}