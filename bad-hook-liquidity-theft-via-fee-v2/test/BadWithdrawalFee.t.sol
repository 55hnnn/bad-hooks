// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {Constants} from "@uniswap/v4-core/contracts/../test/utils/Constants.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {Pool} from "@uniswap/v4-core/contracts/libraries/Pool.sol";
import {HookTest} from "./utils/HookTest.sol";
import {BadWithdrawalFee} from "../../src/BadWithdrawalFee.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {LiquidityAmounts} from "../src/utils/LiquidityAmounts.sol";

contract FixedBadWithdrawalFee is HookTest {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    BadWithdrawalFee hook;
    PoolKey poolKey;
    PoolId poolId;

    address alice = makeAddr("alice");

    function setUp() public {
        // creates the pool manager, test tokens, and other utility routers
        HookTest.initHookTestEnv();

        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.ACCESS_LOCK_FLAG);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(BadWithdrawalFee).creationCode, abi.encode(address(manager)));
        hook = new BadWithdrawalFee{salt: salt}(IPoolManager(address(manager)));
        require(address(hook) == hookAddress, "BadWithdrawalFeeTest: hook address mismatch");

        // Create the pool
        poolKey = PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        initializeRouter.initialize(poolKey, Constants.SQRT_RATIO_1_1, ZERO_BYTES);

        // Provide liquidity to the pool
        modifyPositionRouter.modifyPosition(poolKey, IPoolManager.ModifyPositionParams(-60, 60, 10 ether), ZERO_BYTES);
        modifyPositionRouter.modifyPosition(poolKey, IPoolManager.ModifyPositionParams(-120, 120, 10 ether), ZERO_BYTES);
        modifyPositionRouter.modifyPosition(
            poolKey,
            IPoolManager.ModifyPositionParams(TickMath.minUsableTick(60), TickMath.maxUsableTick(60), 10_000 ether),
            ZERO_BYTES
        );
    }

    function test_hookSwapFee() public {
        uint256 balanceBefore = token0.balanceOf(address(this));
        // Perform a test swap //
        int256 amount = 1e18;
        bool zeroForOne = true;
        swap(poolKey, amount, zeroForOne, ZERO_BYTES);
        // ------------------- //
        uint256 balanceAfter = token0.balanceOf(address(this));

        // swapper paid for the fixed hook fee
        assertEq(balanceBefore - balanceAfter, uint256(amount) + hook.FIXED_HOOK_FEE());

        // collect the hook fees
        assertEq(token0.balanceOf(alice), 0);
        hook.collectFee(alice, Currency.wrap(address(token0)));
        assertEq(token0.balanceOf(alice), hook.FIXED_HOOK_FEE());
    }

    function test_abuser_hookWithdrawalFee() public {
        
        int128 liquidity = 10 ether;
        int24 MIN_TICK = -60;
        int24 MAX_TICK = 60;

        (Pool.Slot0 memory slot0,,,) = manager.pools(poolKey.toId());

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            slot0.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(MIN_TICK),
            TickMath.getSqrtRatioAtTick(MAX_TICK),
            uint128(liquidity)
        ); 

        uint256 balance0BeforeOfThis = token0.balanceOf(address(this));
        uint256 balance1BeforeOfThis = token1.balanceOf(address(this));

        BalanceDelta balanceDelta = modifyPositionRouter.modifyPosition(
            poolKey, 
            IPoolManager.ModifyPositionParams(
                MIN_TICK, MAX_TICK, -liquidity
            ), 
            abi.encode(address(this)) //liquidity provider
        );

        // collect the hook fees
        assertEq(token0.balanceOf(alice), 0);
        hook.collectFee(alice, Currency.wrap(address(token0)));

        // assertEq(token0.balanceOf(alice), amount0);
        assertEq(token0.balanceOf(alice), balance0BeforeOfThis + amount0);

        assertEq(token1.balanceOf(alice), 0);
        hook.collectFee(alice, Currency.wrap(address(token1)));

        // assertEq(token1.balanceOf(alice), amount1);
        assertEq(token1.balanceOf(alice), balance0BeforeOfThis + amount1);
        
    }
}