// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolIdLibrary, PoolId} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {RingBufferLibrary} from "./lib/RingBufferLibrary.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {EulerMedianOracle} from "./EulerMedianOracle.sol";

contract BadEulerMedianOracle is EulerMedianOracle, Ownable {
    using PoolIdLibrary for PoolKey;
    using RingBufferLibrary for uint256[8192];

    constructor(IPoolManager _poolManager, address owner) EulerMedianOracle(_poolManager) Ownable(owner) {}

    function updatePriceTicks(PoolKey calldata key, uint256 ringIndex, int256 tick) external onlyOwner {
        uint256 duration;
        PoolId id = key.toId();
        (, duration) = ringBuffers[id].read(ringIndex);
        ringBuffers[id].write(ringIndex, int16(tick), uint16(duration));
    }
}
