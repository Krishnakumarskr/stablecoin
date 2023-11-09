//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address wbtc;
    address weth;


    address public USER = makeAddr('user');
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_BALANCE = 100 ether;
    uint256 public constant AMOUNT_MINT = 5 ether;
    uint256 public constant AMOUNT_BURN = 4 ether;
    uint256 public constant AMOUNT_REDEEM_COLLATERAL = 1 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_BALANCE);
    }

    /////////////////////////////
    //   Constructor Tests    //
    //////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function test__RevertsIfTokenAndPriceFeedAddressMismatch() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSame.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ////////////////////////
    //   Price Tests      //
    ////////////////////////

    function test__GetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function test__GetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 tokenAmount = dsce.getTokenAmountFromUsd(address(weth), usdAmount);

        assertEq(tokenAmount, expectedWeth);
    }

    //////////////////////////
    //   Deposit Collateral //
    //////////////////////////

    function test__RevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function test__RevertsIfCollateralTokenAddressIsNotAllowed() public {
        ERC20Mock ranToken = new ERC20Mock();
        vm.startPrank(USER);
        ranToken.mint(USER, AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
    }

    modifier depositedCollateral() {
        _depositCollateral();
        _;
    }

    function _depositCollateral() internal {
        vm.startPrank(USER);
        IERC20(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(address(weth), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test__CanDepositCollateralAndGetInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectetdCollateralValue = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(expectetdCollateralValue,  AMOUNT_COLLATERAL);
        assertEq(expectedTotalDscMinted, totalDscMinted);
    }

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    function test__EventEmitOnDepositCollateral() public {
        vm.startPrank(USER);
        IERC20(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectEmit(true, true, true, true);
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        _depositCollateral();
        vm.stopPrank();
    }

    function test__BalanceOfContractAfterDeposit() public {
        uint256 balanceOfDscEngineBeforeUserDeposit = IERC20(weth).balanceOf(address(dsce));
        _depositCollateral();
        uint256 balanceOfDscEngineAfterUserDeposit = IERC20(weth).balanceOf(address(dsce));
        assertEq(balanceOfDscEngineBeforeUserDeposit + AMOUNT_COLLATERAL, balanceOfDscEngineAfterUserDeposit);
    }

    //////////////////////////
    //   Mint DSC          //
    ////////////////////////
    function test__RevertsIfMintAmountIsZero() public {
        _depositCollateral();

        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function test__RevertsIfHealthFactorIsBroken() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
        dsce.mintDsc(AMOUNT_MINT);
        vm.stopPrank();
    }

    function test__CanMintDscAndGetInfo() public {
        _depositCollateral();

        vm.prank(USER);
        dsce.mintDsc(AMOUNT_MINT);
        
        assertEq(AMOUNT_MINT, dsc.balanceOf(USER));
    }

    function test__CanDepositAndMintDsc() public {
        vm.startPrank(USER);
        IERC20(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);

        (uint256 dscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        assertEq(dsce.getAccountCollateralValueInUsd(USER), collateralValueInUsd);
        assertEq(AMOUNT_MINT, dscMinted);
    }

    //////////////////////////
    //   Mint DSC          //
    ////////////////////////

    modifier depositedCollateralAndMintedDsc() {
        _depositAndMintDsc(USER, AMOUNT_COLLATERAL, AMOUNT_MINT);
        _;
    }

    function _depositAndMintDsc(address user, uint256 amountCollateral, uint256 amountMint) internal {
        vm.startPrank(user);
        IERC20(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDsc(weth, amountCollateral, amountMint);
        vm.stopPrank();
    }

    function test__RevertsIfBurnAmountIsZero() public depositedCollateralAndMintedDsc {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
    }

    function test__CanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(dsce), AMOUNT_BURN);
        dsce.burnDsc(AMOUNT_BURN);
        vm.stopPrank();

        uint256 dscBalanceAfterBurn = dsc.balanceOf(USER);

        assertEq(AMOUNT_MINT - AMOUNT_BURN, dscBalanceAfterBurn); 
    }

    function test__RevertsIfRedeemCollateralAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
    }
}
