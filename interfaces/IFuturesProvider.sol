// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

struct FuturesProviderSupportedMetric {
    uint8 metricId;
    string name;
}

/**
 * These methods are to provide information to the DApp about a particular Futures Provider
 */
interface IFuturesProvider {
    /**
     * Provides a human friendly label describing on what this Future Provider enables speculating
     */
    function getLabel() external view returns (string memory);

    /**
     * Provides names of the supported assets
     */
    function getSupportedAssets() external returns (string[] memory);

    /**
     * Provides the available metrics and their names and integer IDs
     */
    function getSupportedMetrics() external returns (FuturesProviderSupportedMetric[] memory);
}