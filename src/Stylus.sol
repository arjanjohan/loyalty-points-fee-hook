// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IStylus} from "./interfaces/IStylus.sol";

contract Stylus is IStylus {

    struct Tier {
        uint256 threshold;
        uint256 discount; // in basis points (10000 = 100%)
    }

    // Loyalty tiers ordered from highest to lowest
    Tier[] public tiers;

    // mapping of address to points
    mapping(address => mapping(address => uint256)) public points;
    
    // mapping of address to last activity block
    mapping(address => uint256) public lastActivityBlock;
    uint24 public baseFee;
    uint256 public expirationBlocks;

    // Initialize BaseHook parent contract in the constructor
    constructor(uint24 _baseFee, uint256 _expirationBlocks) {
        baseFee = _baseFee;
        expirationBlocks = _expirationBlocks;

        // Set default tier values - ordered from highest to lowest
        tiers.push(Tier(0.001 ether, 5000));   // Tier 1: 10000 points, 50% discount
        tiers.push(Tier(0.00005 ether, 2500));    // Tier 2: 1000 points, 25% discount
        tiers.push(Tier(0.000005 ether, 1000));     // Tier 3: 100 points, 10% discount
    }


    function getUserPoints(address user, address currency1) external view returns (uint256) {
        return points[currency1][user];
    }

    function getFee(address user, address currency1) external returns (uint24) {
        // Reset points if user has not been active for the last POINTS_EXPIRATION_BLOCKS blocks
        if (block.number - lastActivityBlock[user] > expirationBlocks) {
            points[currency1][user] = 0;
        }

        uint24 fee = calculateFee(user, currency1);
        return fee;
    }

    function calculateFee(address user, address currency1) internal view returns (uint24) {
        uint256 userPoints = points[currency1][user];

        // Check tiers from highest to lowest to find applicable discount
        for (uint256 i = 0; i < tiers.length; i++) {
            if (userPoints >= tiers[i].threshold) {
                
                // uint24 discountAmount = (baseFee * tiers[i].discount);
                // require(discountAmount <= baseFee, "Discount exceeds base fee");
                
                return uint24(baseFee - ((baseFee * tiers[i].discount) / 10000));
            }
        }

        return baseFee;
    }

    function updatePoints(address user, bool zeroForOne, int256 amountSpecified, int256 deltaAmount0, address currency0, address currency1) external {
        if (zeroForOne) {
            if (amountSpecified < 0) {
                // token0 is being sold, amountSpecified is exact input
                calculatePoints(user, -amountSpecified, currency1);
            } else {
                // token1 is being sold, amountSpecified is exact output
                calculatePoints(user, -deltaAmount0, currency1);
            }
        } else {
            if (amountSpecified > 0) {
                // token1 is being sold, amountSpecified is exact input
                calculatePoints(user, amountSpecified, currency1);
            } else {
                // token0 is being sold, amountSpecified is exact output
                calculatePoints(user, deltaAmount0, currency1);
            }
        }
        lastActivityBlock[user] = block.number;
    }

    function calculatePoints(address user, int256 amountIn, address tokenIn) internal {
        // TODO: convert amountIn to ETH for a more fair points calculation
        points[tokenIn][user] += uint256(amountIn);
    }
}
