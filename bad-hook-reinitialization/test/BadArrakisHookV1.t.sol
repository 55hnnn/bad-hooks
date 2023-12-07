//  SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "forge-std/StdUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {ILockCallback} from "@uniswap/v4-core/contracts/interfaces/callback/ILockCallback.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {Currency} from "@uniswap/v4-core/contracts/libraries/CurrencyLibrary.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {IArrakisHookV1} from "../contracts/interfaces/IArrakisHookV1.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ArrakisHookV1} from "../contracts/ArrakisHookV1.sol";
import "./constants/FeeAmount.sol" as FeeAmount;
import {ArrakisHooksV1Factory} from "./utils/ArrakisHooksV1Factory.sol";
import {ArrakisHookV1Helper} from "./helper/ArrakisHookV1Helper.sol";
import {UniswapV4Swapper} from "./helper/UniswapV4Swapper.sol";

// import {ArrakisHookV1} from "../contracts/ArrakisHookV1.sol";

contract ArrakisHookV1Test is Test {
    //#region constants.

    ArrakisHooksV1Factory public immutable factory;

    //#endregion constants.

    using TickMath for int24;
    using BalanceDeltaLibrary for BalanceDelta;

    PoolManager public poolManager;
    ArrakisHookV1 public arrakisHookV1;
    uint24 public fee;
    IPoolManager.PoolKey public poolKey;

    IERC20 public tokenA;
    IERC20 public tokenB;

    IERC20 public tokenC;
    IERC20 public tokenD;


    constructor() {
        factory = new ArrakisHooksV1Factory();
    }

    ///@dev let's assume for this test suite the price of tokenA/tokenB is equal to 1.

    function setUp() public {
        poolManager = new PoolManager(0);
        tokenA = new ERC20("Token A", "TOA");
        tokenB = new ERC20("Token B", "TOB");

        tokenC = new ERC20("Token C", "TOC");
        tokenD = new ERC20("Token D", "TOD");

        Hooks.Calls memory calls = Hooks.Calls({
            beforeInitialize: true,
            afterInitialize: false,
            beforeModifyPosition: false,
            afterModifyPosition: false,
            beforeSwap: true,
            afterSwap: false, // strategy of the vault
            beforeDonate: false,
            afterDonate: false
        });

        IArrakisHookV1.InitializeParams memory params = IArrakisHookV1
            .InitializeParams({
                poolManager: poolManager,
                name: "HOOK TOKEN",
                symbol: "HOT",
                rangeSize: uint24(FeeAmount.HIGH * 2), /// 2% price range.
                lowerTick: -FeeAmount.HIGH,
                upperTick: FeeAmount.HIGH,
                referenceFee: 200,
                referenceVolatility: 0, // TODO onced implemented in the hook
                ultimateThreshold: 0, // TODO onced implemented in the hook
                allocation: 1000, /// @dev in BPS => 10%
                c: 5000 /// @dev in BPS also => 50%
            });

        address hookAddress;
        (hookAddress, fee) = factory.deployWithPrecomputedHookAddress(
            params,
            calls
        );

        arrakisHookV1 = ArrakisHookV1(hookAddress);
    }


    function test_mint() public {
        address vb = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045; // minter

        deal(address(tokenA), vb, 200);
        deal(address(tokenB), vb, 200);

        uint160 sqrtPriceX96 = int24(1).getSqrtRatioAtTick();
        int16 tickSpacing = 200;

        _initialize(sqrtPriceX96, tickSpacing);

        uint160 sqrtPriceX96A = (-FeeAmount.HIGH).getSqrtRatioAtTick();
        uint160 sqrtPriceX96B = FeeAmount.HIGH.getSqrtRatioAtTick();

        uint128 liquidity = ArrakisHookV1Helper.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtPriceX96A,
            sqrtPriceX96B,
            200,
            200
        );

        vm.startPrank(vb);

        tokenA.approve(address(arrakisHookV1), 200);
        tokenB.approve(address(arrakisHookV1), 200);

        arrakisHookV1.mint(uint256(liquidity), vb);
        assertEq(arrakisHookV1.balanceOf(vb), 20_000);

        vm.stopPrank();
    }

    function test_burn() public {

        // #region minting before burning.

        address vb = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045; // minter

        deal(address(tokenA), vb, 200);
        deal(address(tokenB), vb, 200);

        uint160 sqrtPriceX96 = int24(1).getSqrtRatioAtTick();
        int16 tickSpacing = 200;

        _initialize(sqrtPriceX96, tickSpacing);

        uint160 sqrtPriceX96A = (-FeeAmount.HIGH).getSqrtRatioAtTick();
        uint160 sqrtPriceX96B = FeeAmount.HIGH.getSqrtRatioAtTick();

        uint128 liquidity = ArrakisHookV1Helper.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtPriceX96A,
            sqrtPriceX96B,
            200,
            200
        );

        vm.startPrank(vb);

        tokenA.approve(address(arrakisHookV1), 200);
        tokenB.approve(address(arrakisHookV1), 200);

        arrakisHookV1.mint(uint256(liquidity), vb);


        // #endregion minting before burning.

        // #region burning.

        arrakisHookV1.burn(arrakisHookV1.balanceOf(vb), vb);

        // #endregion burning.

        vm.stopPrank();

        assertEq(199, tokenA.balanceOf(vb));
        assertEq(199, tokenB.balanceOf(vb));
    }

    function test_abuser_burn() public {

        // #region minting before burning.

        address vb = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045; // minter

        deal(address(tokenA), vb, 200);
        deal(address(tokenB), vb, 200);

        uint160 sqrtPriceX96 = int24(1).getSqrtRatioAtTick();
        int16 tickSpacing = 200;

        _initialize(sqrtPriceX96, tickSpacing);

        uint160 sqrtPriceX96A = (-FeeAmount.HIGH).getSqrtRatioAtTick();
        uint160 sqrtPriceX96B = FeeAmount.HIGH.getSqrtRatioAtTick();

        uint128 liquidity = ArrakisHookV1Helper.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtPriceX96A,
            sqrtPriceX96B,
            200,
            200
        );

        vm.startPrank(vb);

        tokenA.approve(address(arrakisHookV1), 200);
        tokenB.approve(address(arrakisHookV1), 200);

        arrakisHookV1.mint(uint256(liquidity), vb);


        // #endregion minting before burning.

        vm.stopPrank();

        // #region attack - reinitialization

        _initializeBadPool(sqrtPriceX96, tickSpacing);

        // #endregion attack - reinitialization

        // #region burning.

        vm.startPrank(vb);

        uint256 vbBalanceABefore = tokenA.balanceOf(vb);
        uint256 vbBalanceBBefore = tokenB.balanceOf(vb);

        arrakisHookV1.burn(arrakisHookV1.balanceOf(vb), vb);

        // #endregion burning.

        vm.stopPrank();

        assertEq(vbBalanceABefore, tokenA.balanceOf(vb));
        assertEq(vbBalanceBBefore, tokenB.balanceOf(vb));
    }

    // #region lockAcquired callback.


    // #endregion lockAcquired callback.

    // #region internal functions.

    function _initialize(
        uint160 sqrtPriceX96_,
        int16 tickSpacing_
    ) internal returns (int24) {
        poolKey = IPoolManager.PoolKey({
            currency0: Currency.wrap(address(tokenA)),
            currency1: Currency.wrap(address(tokenB)),
            fee: fee,
            tickSpacing: tickSpacing_,
            hooks: IHooks(address(arrakisHookV1))
        });

        return poolManager.initialize(poolKey, sqrtPriceX96_);
    }

    function _initializeBadPool(
        uint160 sqrtPriceX96_,
        int16 tickSpacing_
    ) internal returns (int24) {
        poolKey = IPoolManager.PoolKey({
            currency0: Currency.wrap(address(tokenC)),
            currency1: Currency.wrap(address(tokenD)),
            fee: fee,
            tickSpacing: tickSpacing_,
            hooks: IHooks(address(arrakisHookV1))
        });

        return poolManager.initialize(poolKey, sqrtPriceX96_);
    }

    // #endregion internal functions.
}
