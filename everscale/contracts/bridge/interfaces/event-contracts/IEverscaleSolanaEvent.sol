pragma ton-solidity >= 0.39.0;

import "./IBasicEvent.sol";


interface IEverscaleSolanaEvent is IBasicEvent {
    struct EverscaleSolanaEventVoteData {
        uint64 eventTransactionLt;
        uint32 eventTimestamp;
        EverscaleSolanaExecuteAccount[] executeAccounts;
        TvmCell eventData;
    }

    struct EverscaleSolanaEventInitData {
        EverscaleSolanaEventVoteData voteData;
        address configuration;
        address staking;
    }

    struct EverscaleSolanaExecuteAccount {
        uint256 account;
        bool readOnly;
        bool isSigner;
    }
}
