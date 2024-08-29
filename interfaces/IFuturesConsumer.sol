// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

interface IFuturesConsumer {
    function specifyOutcome(uint80 speculationId, bool outcomeWasMet) external;
}