// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IFuturesProvider.sol";
import "../interfaces/IFuturesConsumer.sol";

enum SpeculationStatus { InProgress, YesWon, NoWon }
enum SpeculationTokenType { Yes, No }

struct Speculation {
    uint64 startTime;
    uint64 endTime;
    
    uint80 totalUSDC;
    uint80 totalYesTokens;
    uint80 totalNoTokens;

    SpeculationStatus status;
    uint80 usdcWonPerWinningToken;

    address futuresContractAddress;
    bool futuresOutcomeRequested;
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

    // Add a Futures Contract usable for new speculations
    function addFuturesContract(address futuresAddress) public onlyOwner {
        // Verify as a valid IFuturesProvider
        IFuturesProvider provider = IFuturesProvider(futuresAddress);
        require(provider.isFuturesProvider(), "Invalid");

        futuresContractAddressWhitelist[futuresAddress] = true;
    }

    // Stop people from using a Futures Contract for new speculations
    // Existing speculations will still have the contract
    function removeFuturesContract(address futuresAddress) public onlyOwner {
        delete futuresContractAddressWhitelist[futuresAddress];
    }

    //// Speculations
    mapping(uint80 => Speculation) private speculations;
    uint80 private nextSpeculationId;
    
    event Speculated(address who, uint80 speculationId, uint256 amountInUSDC, SpeculationTokenType tokenType);
    event CashedOut(address who, uint80 speculationId, uint256 amountInUSDC);

    function getSpeculation(uint80 speculationId) private view returns (Speculation storage) {
        require(speculationId < nextSpeculationId, "Speculation does not exist");
        return speculations[speculationId];
    }

    function getNoTokenId(uint80 speculationId) private pure returns (uint256) {
        return uint256(speculationId) << 1;
    }

    function getYesTokenId(uint80 speculationId) private pure returns (uint256) {
        return (uint256(speculationId) << 1) + 1;
    }

    function collectWinnings(uint80 speculationId) public {
        Speculation storage speculation = getSpeculation(speculationId);

        require(
            speculation.status != SpeculationStatus.InProgress,
            "Speculation in progress"
        );

        uint256 winningTokenId = speculation.status == SpeculationStatus.YesWon
            ? getYesTokenId(speculationId)
            : getNoTokenId(speculationId);

        uint256 winningTokenCount = balanceOf(msg.sender, winningTokenId);

        require(winningTokenCount != 0, "No winnings");

        uint256 winningAmountInUSDC = speculation.usdcWonPerWinningToken * winningTokenCount;

        // Burn winning tokens
        _burn(msg.sender, winningTokenId, winningTokenCount);

        // Send USDC to winner
        moveUSDC(address(this), msg.sender, winningAmountInUSDC);

        // Let the world know
        emit CashedOut(msg.sender, speculationId, winningAmountInUSDC);
    }

    function calculateMintAmountPerUSDC(Speculation storage speculation, SpeculationTokenType tokenType) private view returns (uint80) {
        uint64 totalDuration = speculation.endTime - speculation.startTime;
        uint64 timeElapsedSoFar = uint64(block.timestamp) - speculation.startTime;
        uint64 elapsedTimeProportion = timeElapsedSoFar / totalDuration;
        bool timeMoreThanHalfWay = timeElapsedSoFar > (totalDuration >> 1);

        uint256 sigma = timeMoreThanHalfWay
            ? 8 * (1 - elapsedTimeProportion) ** 4
            : 1 - 8 * elapsedTimeProportion ** 4;

        uint256 aTokenTotal = tokenType == SpeculationTokenType.Yes
            ? speculation.totalYesTokens
            : speculation.totalNoTokens;

        uint256 bTokenTotal = tokenType == SpeculationTokenType.No
            ? speculation.totalYesTokens
            : speculation.totalNoTokens;

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

    function _mintSpeculationTokens(uint80 speculationId, uint80 usdcToDeposit, SpeculationTokenType tokenType) private {
        Speculation storage speculation = getSpeculation(speculationId);
    
        // Assert block time
        require(speculation.endTime > block.timestamp, "Speculation is over");

        // Deposit USDC
        moveUSDC(msg.sender, address(this), usdcToDeposit);

        // Calculate mint rate
        uint80 mintAmountPerUSDC = calculateMintAmountPerUSDC(speculation, tokenType);
        uint80 tokensToMint = mintAmountPerUSDC * usdcToDeposit;

        // Mint tokens
        uint256 speculationTokenId = tokenType == SpeculationTokenType.Yes
            ? getYesTokenId(speculationId)
            : getNoTokenId(speculationId);

        _mint(msg.sender, speculationTokenId, tokensToMint, new bytes(0));

        // Update speculation (TODO: check that this stores the updates)
        speculation.totalUSDC += usdcToDeposit;

        if (tokenType == SpeculationTokenType.Yes) {
            speculation.totalYesTokens += tokensToMint;
        } else {
            speculation.totalNoTokens += tokensToMint;
        }

        // Tell the world
        emit Speculated(msg.sender, speculationId, usdcToDeposit, tokenType);
    }

    function mintSpeculationTokens(uint80 speculationId, uint80 usdcToDeposit, SpeculationTokenType tokenType) public {
        _mintSpeculationTokens(speculationId, usdcToDeposit, tokenType);
    }

    function createSpeculation(address futuresContractAddress, uint64 endTime, uint80 usdcToDeposit, SpeculationTokenType tokenType) public {
        // Require minimum deposit to create a speculation
        require(usdcToDeposit >= 25 * 10e6, "Not enough USDC");

        // Prevent speculations from ending in the past
        require(endTime >= block.timestamp, "Cannot end in past");

        // Only allow whitelisted Futures Contracts
        require(futuresContractAddressWhitelist[futuresContractAddress], "Not whitelisted");

        uint80 speculationId = nextSpeculationId;
        ++nextSpeculationId;

        speculations[speculationId] = Speculation({
            startTime: uint64(block.timestamp),
            endTime: endTime,

            totalUSDC: usdcToDeposit,
            totalYesTokens: 1,
            totalNoTokens: 1,

            status: SpeculationStatus.InProgress,
            usdcWonPerWinningToken: 0,

            futuresContractAddress: futuresContractAddress,
            futuresOutcomeRequested: false
        });

        // Mint the tokens
        _mintSpeculationTokens(speculationId, usdcToDeposit, tokenType);
    }

    /// IFuturesConsumer
    function specifyOutcome(uint80 speculationId, bool outcomeWasMet) public {
        Speculation storage speculation = getSpeculation(speculationId);

        require(speculation.futuresContractAddress == msg.sender, "Unauthorised");
        require(speculation.status == SpeculationStatus.InProgress, "Speculation not in progress");
        require(speculation.endTime <= block.timestamp, "Speculation not over");

        speculation.status = outcomeWasMet ? SpeculationStatus.YesWon : SpeculationStatus.NoWon;
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
