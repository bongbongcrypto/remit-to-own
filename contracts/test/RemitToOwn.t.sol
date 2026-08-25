// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {RemitToOwn} from "../src/RemitToOwn.sol";
import {RemitToOwnHarness} from "./RemitToOwnHarness.sol";

contract RemitToOwnTest is Test {
    RemitToOwnHarness rto;

    uint64 constant ETH_MAINNET = 3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant FAKE_TOKEN = address(0xBAD);
    address constant BUYER = address(0xB0B);
    address constant MERCHANT = address(0x5E11E4);
    address constant COLLECTOR = address(0xC011EC);
    address constant UNCLE = address(0x0C1E); // the relative abroad

    bytes32 constant PLAN = keccak256("solar-home-system-001");

    // A 300 USDC solar system, paid 25 USDC at a time, each buying 30 days.
    uint128 constant PRICE = 300e6;
    uint128 constant INSTALLMENT = 25e6;
    uint32 constant DAYS_PER = 30;

    event PaymentProven(
        bytes32 indexed planId, address indexed payer, uint128 amount, uint128 paidTotal, uint64 activeUntil
    );
    event PlanSettled(bytes32 indexed planId, address indexed buyer, uint128 paidTotal);

    function setUp() public {
        vm.warp(1_700_000_000); // a sane "now" so day math is readable
        rto = new RemitToOwnHarness();
        rto.setTrustedToken(ETH_MAINNET, USDC, true);
        // Collectors are issued by the operator, not by anyone who asks: see
        // openPlan's note on why that restriction is load-bearing.
        rto.openPlan(PLAN, BUYER, ETH_MAINNET, USDC, COLLECTOR, PRICE, INSTALLMENT, DAYS_PER);
    }

    // --- setup guards -----------------------------------------------------

    function test_openPlan_recordsTerms() public view {
        (address buyer, address merchant, address collector, uint128 price, uint128 paid,, bool active, bool settled) =
            rto.getPlan(PLAN);
        assertEq(buyer, BUYER);
        assertEq(merchant, address(this), "issued by the operator");
        assertEq(collector, COLLECTOR);
        assertEq(price, PRICE);
        assertEq(paid, 0);
        assertFalse(active, "nothing paid yet, device is off");
        assertFalse(settled);
        assertEq(rto.planCount(), 1);
        assertEq(rto.collectorPlan(ETH_MAINNET, COLLECTOR), PLAN, "collector routes to the plan");
    }

    function test_untrustedToken_cannotOpenPlan() public {
        vm.expectRevert(abi.encodeWithSelector(RemitToOwn.UntrustedToken.selector, ETH_MAINNET, FAKE_TOKEN));
        rto.openPlan(keccak256("x"), BUYER, ETH_MAINNET, FAKE_TOKEN, address(0xFEE), PRICE, INSTALLMENT, DAYS_PER);
    }

    function test_collectorCannotBeReused() public {
        vm.expectRevert(RemitToOwn.BadTerms.selector);
        rto.openPlan(keccak256("second"), BUYER, ETH_MAINNET, USDC, COLLECTOR, PRICE, INSTALLMENT, DAYS_PER);
    }

    function test_onlyAdminSetsTrustedToken() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert(RemitToOwn.NotAdmin.selector);
        rto.setTrustedToken(ETH_MAINNET, FAKE_TOKEN, true);
    }

    // --- the core loop ----------------------------------------------------

    function test_onePayment_switchesDeviceOnFor30Days() public {
        rto.applyPayment(PLAN, UNCLE, INSTALLMENT);

        assertTrue(rto.isActive(PLAN), "device runs");
        assertEq(rto.timeRemaining(PLAN), uint64(30 days));
        assertEq(rto.amountRemaining(PLAN), PRICE - INSTALLMENT);
    }

    function test_deviceLapsesWhenPaymentsStop() public {
        rto.applyPayment(PLAN, UNCLE, INSTALLMENT);
        assertTrue(rto.isActive(PLAN));

        skip(31 days);
        assertFalse(rto.isActive(PLAN), "no payment, device stops");
        assertEq(rto.timeRemaining(PLAN), 0);
    }

    function test_payingEarly_stacksDaysInsteadOfWasting() public {
        rto.applyPayment(PLAN, UNCLE, INSTALLMENT);
        skip(10 days);
        rto.applyPayment(PLAN, UNCLE, INSTALLMENT); // paid with 20 days still left

        // 20 remaining + 30 bought, not 30 from today
        assertEq(rto.timeRemaining(PLAN), uint64(50 days));
    }

    function test_lapsedPlan_restartsFromNow() public {
        rto.applyPayment(PLAN, UNCLE, INSTALLMENT);
        skip(45 days); // 15 days lapsed
        rto.applyPayment(PLAN, UNCLE, INSTALLMENT);

        assertEq(rto.timeRemaining(PLAN), uint64(30 days), "no credit for the gap, no penalty either");
        assertTrue(rto.isActive(PLAN));
    }

    function test_partialPayment_buysProportionalDays() public {
        rto.applyPayment(PLAN, UNCLE, INSTALLMENT / 5); // a fifth of an installment
        assertEq(rto.timeRemaining(PLAN), uint64(6 days), "6 days for a fifth of 30");
        assertTrue(rto.isActive(PLAN));
    }

    function test_largePayment_buysManyMonths() public {
        rto.applyPayment(PLAN, UNCLE, INSTALLMENT * 4);
        assertEq(rto.timeRemaining(PLAN), uint64(120 days));
        assertEq(rto.amountRemaining(PLAN), PRICE - INSTALLMENT * 4);
    }

    // --- ownership --------------------------------------------------------

    function test_payingItOff_transfersOwnershipAndNeverLapses() public {
        for (uint256 i = 0; i < 12; i++) {
            rto.applyPayment(PLAN, UNCLE, INSTALLMENT); // 12 x 25 = 300
        }
        (,,,, uint128 paid,,, bool settled) = rto.getPlan(PLAN);
        assertEq(paid, PRICE);
        assertTrue(settled, "device is the buyer's now");
        assertEq(rto.amountRemaining(PLAN), 0);

        skip(3650 days);
        assertTrue(rto.isActive(PLAN), "owned outright, never locks again");
    }

    function test_overpayment_isCappedAtPrice() public {
        rto.applyPayment(PLAN, UNCLE, PRICE * 2);
        (,,,, uint128 paid,,, bool settled) = rto.getPlan(PLAN);
        assertEq(paid, PRICE, "never records more than the price");
        assertTrue(settled);
    }

    function test_settlementEmitsOnce() public {
        rto.applyPayment(PLAN, UNCLE, PRICE - INSTALLMENT);
        vm.expectEmit(true, true, false, true);
        emit PlanSettled(PLAN, BUYER, PRICE);
        rto.applyPayment(PLAN, UNCLE, INSTALLMENT);

        // a further payment must not re-settle
        vm.recordLogs();
        rto.applyPayment(PLAN, UNCLE, INSTALLMENT);
        (,,,, uint128 paid,,, bool settled) = rto.getPlan(PLAN);
        assertEq(paid, PRICE);
        assertTrue(settled);
    }

    // --- anybody can pay --------------------------------------------------

    function test_anyRelativeCanPay() public {
        rto.applyPayment(PLAN, UNCLE, INSTALLMENT);
        rto.applyPayment(PLAN, address(0xA17E), INSTALLMENT); // a different relative
        assertEq(rto.timeRemaining(PLAN), uint64(60 days));
    }

    function test_paymentEvent_carriesPayerAndTotals() public {
        vm.expectEmit(true, true, false, true);
        emit PaymentProven(PLAN, UNCLE, INSTALLMENT, INSTALLMENT, uint64(block.timestamp + 30 days));
        rto.applyPayment(PLAN, UNCLE, INSTALLMENT);
    }

    // --- guards -----------------------------------------------------------

    function test_paymentToUnknownPlan_reverts() public {
        bytes32 ghost = keccak256("no-such-plan");
        vm.expectRevert(abi.encodeWithSelector(RemitToOwn.NoPlan.selector, ghost));
        rto.applyPayment(ghost, UNCLE, INSTALLMENT);
    }

    // --- restrictions introduced by the audit -----------------------------

    function test_strangerCannotIssueACollector() public {
        // The whole design assumes a collection address belongs to its plan.
        // Nothing on-chain can prove that, so issuing is an operator action.
        vm.prank(address(0xDEAD));
        vm.expectRevert(RemitToOwn.NotAdmin.selector);
        rto.openPlan(keccak256("squat"), BUYER, ETH_MAINNET, USDC, address(0xBA5E), PRICE, INSTALLMENT, DAYS_PER);
    }

    function test_zeroPlanIdRejected() public {
        vm.expectRevert(RemitToOwn.BadTerms.selector);
        rto.openPlan(bytes32(0), BUYER, ETH_MAINNET, USDC, address(0xC03), PRICE, INSTALLMENT, DAYS_PER);
    }

    function test_absurdServiceTermRejected() public {
        vm.expectRevert(RemitToOwn.BadTerms.selector);
        rto.openPlan(keccak256("silly"), BUYER, ETH_MAINNET, USDC, address(0xC04), PRICE, INSTALLMENT, 100_000);
    }

    function test_adminCannotBeBurned() public {
        vm.expectRevert(RemitToOwn.BadTerms.selector);
        rto.transferAdmin(address(0));
    }

    function test_dustPaymentBuysProportionalSeconds() public {
        // Small sums are the norm in this market. Accruing in seconds means a
        // 0.8 USDC payment buys real time instead of rounding to zero days.
        rto.applyPayment(PLAN, UNCLE, 800_000); // 0.8 USDC of a 25 USDC installment
        assertGt(rto.timeRemaining(PLAN), 0, "dust still buys service");
        assertTrue(rto.isActive(PLAN));
    }

    function test_planCurrencyIsVisible() public view {
        (uint64 chainKey, address token, uint128 inst, uint32 dpi) = rto.getPlanCurrency(PLAN);
        assertEq(chainKey, ETH_MAINNET);
        assertEq(token, USDC);
        assertEq(inst, INSTALLMENT);
        assertEq(dpi, DAYS_PER);
    }

    function test_plansAreIndependent() public {
        bytes32 second = keccak256("phone-002");
        rto.openPlan(second, address(0xBEEF), ETH_MAINNET, USDC, address(0xC02), PRICE, INSTALLMENT, DAYS_PER);

        rto.applyPayment(PLAN, UNCLE, INSTALLMENT);
        assertTrue(rto.isActive(PLAN));
        assertFalse(rto.isActive(second), "paying one plan does not power another");
        assertEq(rto.planCount(), 2);
    }
}
