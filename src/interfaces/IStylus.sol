// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStylus {


    function getUserPoints(address user, address currency1) external view returns (uint256);

    function getFee(address user, address currency1) external returns (uint24);
    function updatePoints(address user, bool zeroForOne, int256 amountSpecified, int256 deltaAmount0, address currency0, address currency1) external;
}