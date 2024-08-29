// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

interface IFuturesConsumer {
    /**
     * This method is to be called by a Futures contract on the Sorites contract
     */
    function specifyOutcome(uint80 speculationId, bool outcomeWasMet) external;
}