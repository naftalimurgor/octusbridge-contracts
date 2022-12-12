pragma ton-solidity >= 0.39.0;

import "./IEVMCallback.sol";


interface IMultiVaultEverscaleEventAlien is IEVMCallback {
    function receiveTokenMeta(
        uint256 base_chainId,
        uint160 base_token,
        string name,
        string symbol,
        uint8 decimals
    ) external;

    function receiveAlienTokenRoot(
        address token_
    ) external;

    function getDecodedData() external responsible returns(
        address proxy_,
        address token_,
        address remainingGasTo_,
        uint128 amount_,
        uint160 recipient_,
        EVMCallback callback,
        uint256 base_chainId_,
        uint160 base_token_
    );
}
