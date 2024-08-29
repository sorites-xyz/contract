// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { FunctionsClient } from "@chainlink/contracts@1.2.0/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import { ConfirmedOwner } from "@chainlink/contracts@1.2.0/src/v0.8/shared/access/ConfirmedOwner.sol";
import { FunctionsRequest } from "@chainlink/contracts@1.2.0/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import "../interfaces/IFuturesProvider.sol";
import "../interfaces/IFuturesConsumer.sol";

struct Future {
    string asset;
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
    // Addresses in https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=2&search=usd
    mapping (string => address) public chainlinkPriceOracles;
    string[] public supportedAssets;

    function addSupportedAsset(string calldata asset, address oracleAddress) public onlyOwner {
        require(chainlinkPriceOracles[asset] == address(0), "Exists");

        // Ensure the address points to a valid AggregatorV3Interface
        AggregatorV3Interface aggregator = AggregatorV3Interface(oracleAddress);
        aggregator.version();

        supportedAssets.push(asset);
        chainlinkPriceOracles[asset] = oracleAddress;
    }

    function getSupportedAssets() public view returns (string[] memory) {
        return supportedAssets;
    }

    //// FuturesProvider
    address private consumerAddress;
    IFuturesConsumer private consumer;
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

        futures[speculationId] = Future("TEMP", metric, value, endTime);
    }


    /**
     * This function is how the public can request for a speculation to be concluded.
     *
     * {aggregatorRoundId} is the Round ID from Chainlink, and it must be such that
     * {aggregatorRoundId} is on/after the endTime but {aggregatorRoundId - 1} is before the endTime.
     * This is to ensure that we use the earliest available round that falls on/after the endTime.
     */
    function requestFutureOutcome(uint80 speculationId, uint80 aggregatorRoundId) public {
        Future storage future = futures[speculationId];
        address oracleAddress = chainlinkPriceOracles[future.asset];

        require(oracleAddress != address(0), "Bad speculationId");

        AggregatorV3Interface aggregator = AggregatorV3Interface(oracleAddress);

        uint80 answer = getRoundPrice(
            future.endTime,
            aggregatorRoundId,
            aggregator
        );

        bool outcomeWasMet;

        if (future.metric == METRIC_PRICE_LESS_THAN) {
            outcomeWasMet = future.value < answer;
        } else if (future.metric == METRIC_PRICE_MORE_THAN_OR_EQUAL_TO) {
            outcomeWasMet = future.value >= answer;
        } else {
            revert("Bad metric");
        }

        consumer.specifyOutcome(speculationId, outcomeWasMet);
    }

    function getRoundPrice(uint80 endTime, uint80 aggregatorRoundId, AggregatorV3Interface aggregator) private view returns (uint80) {
        // Target round must be on or after the endTime
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = aggregator.getRoundData(aggregatorRoundId);

        require(updatedAt >= endTime, "Bad round (1)");

        // Round before target must be before the endTime
        (
            uint80 _roundId,
            int256 _answer,
            uint256 _startedAt,
            uint256 beforeUpdatedAt,
            uint80 _answeredInRound
        ) = aggregator.getRoundData(aggregatorRoundId - 1);

        require(beforeUpdatedAt < endTime, "Bad round (2)");

        // Now we know that {answer} is the earliest available answer
        // that's still on/after the {endTime}

        require(answer < 0, "Bad answer");

        return uint80(uint256(answer));
    }

    //// Internal
    constructor(address initialConsumerAddress) ConfirmedOwner(msg.sender) {
        consumerAddress = initialConsumerAddress;
        consumer = IFuturesConsumer(initialConsumerAddress);
    }
}