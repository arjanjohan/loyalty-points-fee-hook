// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStylus {

    function getTotalPoints() external view returns (uint256);

    function getUserPoints(address user) external view returns (uint256);

    function getFee(address user) external returns (uint24);
    function updatePoints(address user, bool zeroForOne, int256 amountSpecified, int256 deltaAmount0, address currency0, address currency1) external;
}