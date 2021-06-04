pragma ton-solidity ^0.39.0;


import "../interfaces/IStaking.sol";
import "../interfaces/IBridge.sol";


import "./../../../node_modules/@broxus/contracts/contracts/utils/RandomNonce.sol";
import "./../../../node_modules/@broxus/contracts/contracts/libraries/MsgFlag.sol";


/*
    @title Staking contract mockup
    Simply approve each event action without any real checks
*/
contract StakingMockup is IStaking, RandomNonce {
    address public bridge;

    constructor(address _bridge) public {
        tvm.accept();

        bridge = _bridge;
    }

    function confirmEthereumEvent(
        IEvent.EthereumEventVoteData eventVoteData,
        uint32 configurationID,
        address relay
    ) override public {
        IBridge(bridge).confirmEthereumEventCallback{ flag: MsgFlag.REMAINING_GAS }(
            eventVoteData,
            configurationID,
            relay
        );
    }

    function rejectEthereumEvent(
        IEvent.EthereumEventVoteData eventVoteData,
        uint32 configurationID,
        address relay
    ) override public {
        IBridge(bridge).rejectEthereumEventCallback{ flag: MsgFlag.REMAINING_GAS }(
            eventVoteData,
            configurationID,
            relay
        );
    }

    function confirmTonEvent(
        IEvent.TonEventVoteData eventVoteData,
        bytes eventDataSignature,
        uint32 configurationID,
        address relay
    ) override public {
        IBridge(bridge).confirmTonEventCallback{ flag: MsgFlag.REMAINING_GAS }(
            eventVoteData,
            eventDataSignature,
            configurationID,
            relay
       );
    }

    function rejectTonEvent(
        IEvent.TonEventVoteData eventVoteData,
        uint32 configurationID,
        address relay
    ) override public {
        IBridge(bridge).rejectTonEventCallback{ flag: MsgFlag.REMAINING_GAS }(
            eventVoteData,
            configurationID,
            relay
        );
    }
}
