// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IStylus} from "./interfaces/IStylus.sol";

contract Stylus is IStylus {


    // mapping of address to points
    mapping(address => uint256) public points;
    // mapping of address to last activity block
    mapping(address => uint256) public lastActivityBlock;
    uint256 public totalPoints;
    uint24 public baseFee;
    uint256 public expirationBlocks;

    // Initialize BaseHook parent contract in the constructor
    constructor(uint24 _baseFee, uint256 _expirationBlocks) {
        baseFee = _baseFee;
        expirationBlocks = _expirationBlocks;
    }

    function getTotalPoints() external view returns (uint256) {
        return totalPoints;
    }   

    function getUserPoints(address user) external view returns (uint256) {
        return points[user];
    }

    function getFee(address user) external returns (uint24) {
        // Reset points if user has not been active for the last POINTS_EXPIRATION_BLOCKS blocks
        if (block.number - lastActivityBlock[user] > expirationBlocks) {
            totalPoints -= points[user];
            points[user] = 0;
        }

        uint24 fee = calculateFee(user);
        return fee;
    }



    function calculateFee(address user) internal view returns (uint24) {
        uint256 userPoints = points[user];

        // if fees above threshold, give discount
        if (userPoints > 200) {
            return baseFee / 2;
        }

        return baseFee;
    }

    function updatePoints(address user, bool zeroForOne, int256 amountSpecified, int256 deltaAmount0, address currency0, address currency1) external {
        if (zeroForOne) {
            if (amountSpecified < 0) {
                // token0 is being sold, amountSpecified is exact input
                calculatePoints(user, -amountSpecified, currency0);
            } else {
                // token1 is being sold, amountSpecified is exact output
                calculatePoints(user, -deltaAmount0, currency0);
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
        points[user] += uint256(amountIn);
        totalPoints += uint256(amountIn);
    }
}
