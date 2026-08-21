// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {RemitToOwn} from "../src/RemitToOwn.sol";

/// @notice Test-only subclass exposing the payment rule so it can be exercised
///         without the BlockProver precompile or the EVM decoder. Those two are
///         validated live on CC3 with real Ethereum transactions instead.
contract RemitToOwnHarness is RemitToOwn {
    function applyPayment(bytes32 planId, address payer, uint128 amount) external {
        _applyPayment(planId, payer, amount);
    }

    /// @notice Run one proven transfer through the full acceptance rules, the
    ///         way _processAndEmitEvent does, without needing a real proof.
    function creditTransferLog(uint64 chainKey, address emitter, address from, address to, uint256 amount)
        external
        returns (bool)
    {
        _setChainKey(chainKey);
        bool ok = _creditTransferLog(emitter, from, to, amount);
        _setChainKey(0);
        return ok;
    }
}
