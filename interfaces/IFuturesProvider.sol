// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

struct SupportedMetric {
  uint8 metricId;
  string name;
  string[] valueLabels;
}

/**
 * This struct is used to provide substitutions.
 * 
 * E.g. (format: "usdc", text: VALUE, value: 1230000)
 * Would replace VALUE with $1.23
 * 
 * Formats are hard coded in the DApp
 */
struct LabelVariable {
  string format;
  string text;
  int256 value;
}

/**
 * These methods are to provide information to the DApp about a particular Futures Provider
 */
interface IFuturesProvider {
  /**
   * Provides a human friendly label describing on what this Futures Provider enables speculating
   */
  function getLabel() external view returns (string memory);

  /**
   * Provides names of the supported assets
   */
  function getSupportedAssets() external view returns (string[] memory);

  /**
   * Provides the available metrics and their names and integer IDs
   */
  function getSupportedMetrics() external view returns (SupportedMetric[] memory);

  /**
   * Creates a new Market Event, returning the Market Event ID
   */
  function createMarketEvent(
    string calldata asset,
    uint8 metric,
    int80[] calldata values,
    uint64 endTime,
    uint80 usdcToDeposit,
    bool speculatingOnYes
  ) external returns (uint80);

  /**
   * Provides a human friendly label for a Market Event
   * 
   * Always available: START_DATE, END_DATE
  */
  function getMarketEventName(uint80 marketEventId) external view returns (string memory);

  /**
   * Provides substitution variables for Uint256s for the Market Event label
   * 
   * The variables START_DATE and END_DATE are always available
   */
  function getMarketEventNameVariables(uint80 marketEventId) external view returns (LabelVariable[] memory);
}