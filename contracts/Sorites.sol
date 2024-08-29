// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/IFuturesConsumer.sol";

enum MarketEventStatus { InProgress, YesWon, NoWon }

struct MarketEvent {
    uint64 startTime;
    uint64 endTime;
    
    uint80 totalUSDC;
    uint80 totalYesTokens;
    uint80 totalNoTokens;

    MarketEventStatus status;
    uint80 usdcWonPerWinningToken;

    address futuresContractAddress;
}

contract Sorites is ERC1155, Ownable, IFuturesConsumer {
    //// USDC
    // Hard coded official USDC contract: https://basescan.org/token/0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
    IERC20 private constant contractForUSDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

    function moveUSDC(address from, address to, uint256 amount) private {
        bool success = contractForUSDC.transferFrom(from, to, amount);

        require(success, "USDC transfer failed");
    }

    //// Futures Contract Interface
    mapping(address => bool) public futuresContractAddressWhitelist;

    // Authorise a Futures Contract to create and resolve Market Events
    function addFuturesContract(address futuresAddress) public onlyOwner {
        futuresContractAddressWhitelist[futuresAddress] = true;
    }

    // Stop people from using a Futures Contract for new Market Events
    // Existing Market Events will still have the contract
    function removeFuturesContract(address futuresAddress) public onlyOwner {
        delete futuresContractAddressWhitelist[futuresAddress];
    }

    //// Market Events
    mapping(uint80 => MarketEvent) private marketEvents;
    uint80 private nextMarketEventId;
    
    event MarketEventResolved(address who, uint80 marketEventId, uint256 amountInUSDC, bool tokenTypeYes);
    event CashedOut(address who, uint80 marketEventId, uint256 amountInUSDC);

    function getMarketEvent(uint80 marketEventId) private view returns (MarketEvent storage) {
        require(marketEventId < nextMarketEventId, "MarketEvent does not exist");
        return marketEvents[marketEventId];
    }

    function getNoTokenId(uint80 marketEventId) private pure returns (uint256) {
        return uint256(marketEventId) << 1;
    }

    function getYesTokenId(uint80 marketEventId) private pure returns (uint256) {
        return (uint256(marketEventId) << 1) + 1;
    }

    function collectWinnings(uint80 marketEventId) public {
        MarketEvent storage marketEvent = getMarketEvent(marketEventId);

        require(
            marketEvent.status != MarketEventStatus.InProgress,
            "MarketEvent in progress"
        );

        uint256 winningTokenId = marketEvent.status == MarketEventStatus.YesWon
            ? getYesTokenId(marketEventId)
            : getNoTokenId(marketEventId);

        uint256 winningTokenCount = balanceOf(msg.sender, winningTokenId);

        require(winningTokenCount != 0, "No winnings");

        uint256 winningAmountInUSDC = marketEvent.usdcWonPerWinningToken * winningTokenCount;

        // Burn winning tokens
        _burn(msg.sender, winningTokenId, winningTokenCount);

        // Send USDC to winner
        moveUSDC(address(this), msg.sender, winningAmountInUSDC);

        // Let the world know
        emit CashedOut(msg.sender, marketEventId, winningAmountInUSDC);
    }

    function calculateMintAmountPerUSDC(MarketEvent storage marketEvent, bool tokenTypeYes) private view returns (uint80) {
        uint64 totalDuration = marketEvent.endTime - marketEvent.startTime;
        uint64 timeElapsedSoFar = uint64(block.timestamp) - marketEvent.startTime;
        uint64 elapsedTimeProportion = timeElapsedSoFar / totalDuration;
        bool timeMoreThanHalfWay = timeElapsedSoFar > (totalDuration >> 1);

        uint256 sigma = timeMoreThanHalfWay
            ? 8 * (1 - elapsedTimeProportion) ** 4
            : 1 - 8 * elapsedTimeProportion ** 4;

        uint256 aTokenTotal = tokenTypeYes
            ? marketEvent.totalYesTokens
            : marketEvent.totalNoTokens;

        uint256 bTokenTotal = tokenTypeYes
            ? marketEvent.totalNoTokens
            : marketEvent.totalYesTokens;

        require(bTokenTotal <= aTokenTotal, "Invalid state");

        uint256 p =
            aTokenTotal <= bTokenTotal
            ? aTokenTotal / bTokenTotal
            : bTokenTotal / aTokenTotal;

        uint256 a = 2 * (1 - p + (1 - p) ** 2);

        uint256 fOfT =
            p + a * elapsedTimeProportion - (a + p) * elapsedTimeProportion ** 2;

        uint256 swapMultiplier = aTokenTotal <= bTokenTotal ? (sigma * p) / fOfT : (sigma * fOfT) / p;

        if (aTokenTotal <= bTokenTotal) {
            return uint80(swapMultiplier >= 1 ? swapMultiplier : 1);
        } else {
            return 1;
        }
    }

    function _mintMarketEventTokens(address minter, uint80 marketEventId, uint80 usdcToDeposit, bool tokenTypeYes) private {
        MarketEvent storage marketEvent = getMarketEvent(marketEventId);
    
        // Assert block time
        require(marketEvent.endTime > block.timestamp, "MarketEvent is over");

        // Deposit USDC
        moveUSDC(minter, address(this), usdcToDeposit);

        // Calculate mint rate
        uint80 mintAmountPerUSDC = calculateMintAmountPerUSDC(marketEvent, tokenTypeYes);
        uint80 tokensToMint = mintAmountPerUSDC * usdcToDeposit;

        // Mint tokens
        uint256 marketEventTokenId = tokenTypeYes
            ? getYesTokenId(marketEventId)
            : getNoTokenId(marketEventId);

        _mint(minter, marketEventTokenId, tokensToMint, new bytes(0));

        // Update marketEvent (TODO: check that this stores the updates)
        marketEvent.totalUSDC += usdcToDeposit;

        if (tokenTypeYes) {
            marketEvent.totalYesTokens += tokensToMint;
        } else {
            marketEvent.totalNoTokens += tokensToMint;
        }

        // Tell the world
        emit MarketEventResolved(minter, marketEventId, usdcToDeposit, tokenTypeYes);
    }

    function mintMarketEventTokens(uint80 marketEventId, uint80 usdcToDeposit, bool tokenTypeYes) public {
        _mintMarketEventTokens(msg.sender, marketEventId, usdcToDeposit, tokenTypeYes);
    }

    /// IFuturesConsumer
    function specifyOutcome(uint80 marketEventId, bool outcomeWasMet) public {
        MarketEvent storage marketEvent = getMarketEvent(marketEventId);

        require(marketEvent.futuresContractAddress == msg.sender, "Unauthorised");
        require(marketEvent.status == MarketEventStatus.InProgress, "MarketEvent not in progress");
        require(marketEvent.endTime <= block.timestamp, "MarketEvent not over");

        marketEvent.status = outcomeWasMet ? MarketEventStatus.YesWon : MarketEventStatus.NoWon;
    }

    function createMarketEvent(address minter, uint64 endTime, uint80 usdcToDeposit, bool tokenTypeYes) external returns (uint80) {
        // Require minimum deposit to create a marketEvent
        require(usdcToDeposit >= 25 * 10e6, "Not enough USDC");

        // Prevent marketEvents from ending in the past
        require(endTime >= block.timestamp, "Cannot end in past");

        // Only allow whitelisted Futures Contracts
        require(futuresContractAddressWhitelist[msg.sender], "Not whitelisted");

        uint80 marketEventId = nextMarketEventId;
        ++nextMarketEventId;

        marketEvents[marketEventId] = MarketEvent({
            startTime: uint64(block.timestamp),
            endTime: endTime,

            totalUSDC: usdcToDeposit,
            totalYesTokens: 1,
            totalNoTokens: 1,

            status: MarketEventStatus.InProgress,
            usdcWonPerWinningToken: 0,

            futuresContractAddress: msg.sender
        });

        // Mint the tokens
        _mintMarketEventTokens(minter, marketEventId, usdcToDeposit, tokenTypeYes);

        return marketEventId;
    }

    //// Internal
    constructor()
        payable
        ERC1155("https://app.sorites.xyz/api/v1/tokens/{id}.json")
        Ownable(msg.sender) {}

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }
}
