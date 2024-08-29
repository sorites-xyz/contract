// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { FunctionsClient } from "@chainlink/contracts@1.2.0/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import { ConfirmedOwner } from "@chainlink/contracts@1.2.0/src/v0.8/shared/access/ConfirmedOwner.sol";
import { FunctionsRequest } from "@chainlink/contracts@1.2.0/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

import "../interfaces/IFuturesProvider.sol";
import "../interfaces/IFuturesConsumer.sol";

struct Future {
    uint8 metric;
    uint80 value;
    uint64 endTime;
}

/**
 * This contract resolved Sorites speculations to Yes or No depending
 * on the price of an asset after a specified time.
**/
contract SoritesPriceFuturesProvider is IFuturesProvider, ConfirmedOwner {
    //// Price Oracles
    mapping (string => address) public chainlinkPriceOracles;
    string[] public supportedAssets;

    function addSupportedAsset(string calldata asset, address oracleAddress) public onlyOwner {
        require(chainlinkPriceOracles[asset] == address(0), "Exists");

        supportedAssets.push(asset);
        chainlinkPriceOracles[asset] = oracleAddress;
    }

    function getSupportedAssets() external view returns (string[] memory) {
        return supportedAssets;
    }

    //// FuturesProvider
    address private consumerAddress;
    mapping (uint80 => Future) futures;

    function isFuturesProvider() view external returns (bool) {
        require(msg.sender == consumerAddress, "Unauthorised");
        return true;
    }

    function createFuture(
        uint80 speculationId,
        uint8 metric,
        uint80 value,
        uint64 endTime
    ) external {
        require(msg.sender == consumerAddress, "Unauthorised");
        require(metric == METRIC_PRICE_LESS_THAN || metric == METRIC_PRICE_MORE_THAN_OR_EQUAL_TO, "Unsupported");

        futures[speculationId] = Future(metric, value, endTime);
    }

    function requestFutureOutcome(uint80 speculationId) external {
    }

    //// Internal
    constructor(address initialConsumerAddress) ConfirmedOwner(msg.sender) {
        consumerAddress = initialConsumerAddress;
    }
}