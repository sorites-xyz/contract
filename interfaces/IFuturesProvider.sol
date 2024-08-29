// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

uint8 constant METRIC_PRICE_LESS_THAN = 1;
uint8 constant METRIC_PRICE_MORE_THAN_OR_EQUAL_TO = 2;

interface IFuturesProvider {
    function isFuturesProvider() external returns (bool);

    function createFuture(
        uint80 speculationId,
        uint8 metric,
        uint80 value,
        uint64 endTime
    ) external;
}