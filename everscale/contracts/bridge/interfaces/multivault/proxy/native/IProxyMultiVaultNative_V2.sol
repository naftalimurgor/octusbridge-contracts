pragma ton-solidity >= 0.39.0;

import "../../IEVMCallback.sol";


interface IProxyMultiVaultNative_V2 is IEVMCallback {
    struct Configuration {
        address everscaleConfiguration;
        address[] evmConfigurations;
        uint128 deployWalletValue;
    }

    function apiVersion() external view responsible returns(uint8);

    function getConfiguration() external view responsible returns (Configuration);
    function setConfiguration(Configuration _config, address gasBackAddress) external;

    event NativeTransfer(
        int8 token_wid,
        uint256 token_addr,
        string name,
        string symbol,
        uint8 decimals,
        uint128 amount,
        uint160 recipient,
        uint256 chainId,
        uint160 callback_recipient,
        TvmCell callback_payload,
        bool callback_strict
    );
}
