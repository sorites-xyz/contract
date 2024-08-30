// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { FunctionsClient } from "@chainlink/contracts@1.2.0/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import { ConfirmedOwner } from "@chainlink/contracts@1.2.0/src/v0.8/shared/access/ConfirmedOwner.sol";
import { FunctionsRequest } from "@chainlink/contracts@1.2.0/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import "../interfaces/IFuturesConsumer.sol";
import "../interfaces/IFuturesProvider.sol";

uint8 constant METRIC_PRICE_LESS_THAN = 1;
uint8 constant METRIC_PRICE_MORE_THAN_OR_EQUAL_TO = 2;

struct Future {
    bool exists;
    string asset;
    uint8 metric;
    uint80 value;
    uint64 endTime;
}

/**
 * This contract resolved Sorites marketEvents to Yes or No depending
 * on the price of an asset after a specified time.
**/
contract SoritesPriceFuturesProvider is ConfirmedOwner, IFuturesProvider {
    //// Price Oracles
    // Addresses in https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=2&search=usd
    mapping (string => address) public chainlinkPriceOracles;
    mapping (string => bool) private supportedAssetsSet;
    string[] public supportedAssets;

    function addSupportedAsset(string calldata asset, address oracleAddress) public onlyOwner {
        require(chainlinkPriceOracles[asset] == address(0), "Exists");

        // Ensure the address points to a valid AggregatorV3Interface
        AggregatorV3Interface aggregator = AggregatorV3Interface(oracleAddress);
        aggregator.version();

        supportedAssets.push(asset);
        chainlinkPriceOracles[asset] = oracleAddress;
        supportedAssetsSet[asset] = true;
    }

    //// FuturesProvider
    address public consumerAddress;
    IFuturesConsumer private consumer;
    mapping (uint80 => Future) futures;

    /**
     * This function is to be used by the public to create a Market Event
     */
    function createMarketEvent(
        string calldata asset,
        uint8 metric,
        uint80 value,
        uint64 endTime,
        uint80 usdcToDeposit,
        bool speculatingOnYes
    ) public returns (uint80) {
        require(metric == METRIC_PRICE_LESS_THAN || metric == METRIC_PRICE_MORE_THAN_OR_EQUAL_TO, "Bad metric");
        require(supportedAssetsSet[asset], "Bad asset");
        require(value >= 1, "Bad value");

        uint80 marketEventId = consumer.createMarketEvent(msg.sender, endTime, usdcToDeposit, speculatingOnYes);

        // Assert that the existing future doesn't exist
        require(!futures[marketEventId].exists, "Existing");

        futures[marketEventId] = Future(true, asset, metric, value, endTime);

        return marketEventId;
    }

    /**
     * This function is how the public can request for a marketEvent to be resolved.
     *
     * {aggregatorRoundId} is the Round ID from Chainlink, and it must be such that
     * {aggregatorRoundId} is on/after the endTime but {aggregatorRoundId - 1} is before the endTime.
     * This is to ensure that we use the earliest available round that falls on/after the endTime.
     */
    function resolveMarketEvent(uint80 marketEventId, uint80 aggregatorRoundId) public {
        Future storage future = futures[marketEventId];

        // Future must exist
        require(future.exists, "Bad marketEventId");

        address oracleAddress = chainlinkPriceOracles[future.asset];

        require(oracleAddress != address(0), "Bad marketEventId");

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

        // Resolve the Market Event
        consumer.resolveMarketEvent(marketEventId, outcomeWasMet);
        
        // Stop storing the Future, so that this method cannot be called again for the {marketEventId}
        delete futures[marketEventId];
    }

    function getRoundPrice(uint80 endTime, uint80 aggregatorRoundId, AggregatorV3Interface aggregator) private view returns (uint80) {
        // Get the current and previous Aggregator Round Data
        (,int256 answer,,uint256 updatedAt,) = aggregator.getRoundData(aggregatorRoundId);
        (,,,uint256 previousUpdatedAt,) = aggregator.getRoundData(aggregatorRoundId - 1);

        // Target round must be on or after the endTime
        require(updatedAt >= endTime, "Bad round (1)");

        // Round before target must be before the endTime
        require(previousUpdatedAt < endTime, "Bad round (2)");

        // Now we know that {answer} is the earliest available answer that's still on/after the {endTime}
        require(answer < 0, "Bad answer");

        return uint80(uint256(answer));
    }

    //// Public info methods
    function getLabel() public pure returns (string memory) {
        return "Price on a future day";
    }

    function getSupportedAssets() public view returns (string[] memory) {
        return supportedAssets;
    }

    function getSupportedMetrics() public pure returns (FuturesProviderSupportedMetric[] memory) {
        FuturesProviderSupportedMetric[] memory supportedMetricsValues;
    
        supportedMetricsValues[0] = FuturesProviderSupportedMetric(METRIC_PRICE_LESS_THAN, "Price is less than");
        supportedMetricsValues[1] = FuturesProviderSupportedMetric(METRIC_PRICE_MORE_THAN_OR_EQUAL_TO, "Price is more than or equal to");
    
        return supportedMetricsValues;
    }

    //// Internal
    constructor(address initialConsumerAddress) ConfirmedOwner(msg.sender) {
        consumerAddress = initialConsumerAddress;
        consumer = IFuturesConsumer(initialConsumerAddress);
    }
}