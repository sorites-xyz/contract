// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

/**
 * These methods are to be called by a Futures contract on the Sorites contract
 */
interface IFuturesConsumer {
    /**
     * Ends a Market Event with a particular outcome
     */
    function specifyOutcome(uint80 speculationId, bool outcomeWasMet) external;

    /**
     * Creates a new market event on behalf of the {minter}
     */
    function createMarketEvent(address minter, uint64 endTime, uint80 usdcToDeposit, bool bankingOnYes) external returns (uint80);
}