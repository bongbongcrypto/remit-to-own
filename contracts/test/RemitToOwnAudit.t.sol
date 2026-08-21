// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {RemitToOwn} from "../src/RemitToOwn.sol";
import {RemitToOwnHarness} from "./RemitToOwnHarness.sol";
import {INativeQueryVerifier} from "../src/VerifierInterface.sol";

/// @notice Regression suite for an adversarial audit of RemitToOwn. Each test
///         names the attack it closes; every one of these was a working exploit
///         before the fixes landed.
contract RemitToOwnAuditTest is Test {
    RemitToOwnHarness rto;

    uint64 constant ETH = 3;
    uint64 constant OTHER_CHAIN = 77;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // 6 decimals
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // 18 decimals
    address constant BUYER = address(0xB0B);
    address constant COLLECTOR = address(0xC011EC);
    address constant UNCLE = address(0x0C1E);
    address constant ATTACKER = address(0xBAD);

    bytes32 constant PLAN = keccak256("plan-1");
    uint128 constant PRICE = 300e6;
    uint128 constant INSTALLMENT = 25e6;
    uint32 constant DAYS_PER = 30;

    function setUp() public {
        vm.warp(1_700_000_000);
        rto = new RemitToOwnHarness();
        rto.setTrustedToken(ETH, USDC, true);
        rto.openPlan(PLAN, BUYER, ETH, USDC, COLLECTOR, PRICE, INSTALLMENT, DAYS_PER);
    }

    // --- C-01: squatting a collection address -----------------------------

    function test_C01_strangerCannotNameACollectorTheyDoNotControl() public {
        // The original exploit: name a busy exchange wallet as your collector,
        // wait for any stranger's deposit, and claim it as your own payment.
        vm.prank(ATTACKER);
        vm.expectRevert(RemitToOwn.NotAdmin.selector);
        rto.openPlan(keccak256("squat"), ATTACKER, ETH, USDC, address(0xE0C1A), 1e6, 1e6, 1);
    }

    function test_C01_squattingCannotDosARealMerchantEither() public {
        // The same restriction closes the denial of service: an attacker can no
        // longer burn a collection address a merchant is about to use.
        vm.prank(ATTACKER);
        vm.expectRevert(RemitToOwn.NotAdmin.selector);
        rto.openPlan(keccak256("dos"), ATTACKER, ETH, USDC, address(0xFEE), 1, 1, 1);
    }

    // --- C-02: any accepted token crediting any plan ----------------------

    function test_C02_aDifferentTokenCannotPayThisPlan() public {
        // DAI is accepted money on this chain, but this plan is denominated in
        // USDC. Before the fix, 300e6 wei of DAI (a ten-billionth of a dollar)
        // settled a 300 USDC plan outright.
        rto.setTrustedToken(ETH, DAI, true);

        bool credited = rto.creditTransferLog(ETH, DAI, UNCLE, COLLECTOR, PRICE);
        assertFalse(credited, "wrong currency is not a payment");
        (,,,, uint128 paid,,, bool settled) = rto.getPlan(PLAN);
        assertEq(paid, 0);
        assertFalse(settled);
    }

    function test_C02_theRightTokenStillPays() public {
        assertTrue(rto.creditTransferLog(ETH, USDC, UNCLE, COLLECTOR, INSTALLMENT));
        (,,,, uint128 paid,,,) = rto.getPlan(PLAN);
        assertEq(paid, INSTALLMENT);
    }

    // --- M-02: proof verified for one chain, credited to another ----------

    function test_M02_proofFromAnotherChainCannotCreditThisPlan() public {
        rto.setTrustedToken(OTHER_CHAIN, USDC, true);
        bool credited = rto.creditTransferLog(OTHER_CHAIN, USDC, UNCLE, COLLECTOR, INSTALLMENT);
        assertFalse(credited, "the plan is paid on Ethereum, not chain 77");
    }

    function test_M02_directExecuteIsRefused() public {
        // execute() is external on the base contract. Called directly there is
        // no chain key in flight, so a payment could be attributed to chain 0.
        INativeQueryVerifier.MerkleProofEntry[] memory noSiblings;
        vm.expectRevert();
        rto.execute(0, ETH, 1, hex"00", bytes32(0), noSiblings, bytes32(0), new bytes32[](0));
    }

    // --- M-01: uint128 truncation -----------------------------------------

    function test_M01_absurdValueIsRejectedNotTruncated() public {
        // 2^128 + PRICE truncates to exactly PRICE, which used to settle the
        // plan for free.
        uint256 monstrous = (uint256(1) << 128) + PRICE;
        assertFalse(rto.creditTransferLog(ETH, USDC, UNCLE, COLLECTOR, monstrous), "rejected outright");
        (,,,, uint128 paid,,, bool settled) = rto.getPlan(PLAN);
        assertEq(paid, 0);
        assertFalse(settled);
    }

    function test_M01_exactlyTwoToThe128IsAlsoRejected() public {
        // Non-zero, so it passed the old zero guard, then truncated to zero.
        assertFalse(rto.creditTransferLog(ETH, USDC, UNCLE, COLLECTOR, uint256(1) << 128));
    }

    // --- M-03: transfers that move no money -------------------------------

    function test_M03_selfTransferBuysNothing() public {
        // A log where from == to leaves the balance untouched, so it must not
        // buy service time.
        assertFalse(rto.creditTransferLog(ETH, USDC, COLLECTOR, COLLECTOR, INSTALLMENT));
        assertFalse(rto.isActive(PLAN), "device stays off");
    }

    // --- L-04: payments after the plan is paid off ------------------------

    function test_L04_paymentAfterSettlementIsNotSwallowed() public {
        rto.creditTransferLog(ETH, USDC, UNCLE, COLLECTOR, PRICE);
        (,,,, uint128 paid,,, bool settled) = rto.getPlan(PLAN);
        assertEq(paid, PRICE);
        assertTrue(settled);

        // A relative who did not know it was finished sends more. It must not
        // report success and vanish.
        assertFalse(rto.creditTransferLog(ETH, USDC, UNCLE, COLLECTOR, PRICE), "not counted as a payment");
    }

    // --- L-01: activeUntil wrapping ---------------------------------------

    function test_L01_serviceTermIsCapped() public {
        // The wrap needed daysPerInstallment in the millions; the cap makes
        // such a plan impossible to open at all.
        vm.expectRevert(RemitToOwn.BadTerms.selector);
        rto.openPlan(keccak256("wrap"), BUYER, ETH, USDC, address(0xC0DE), PRICE, 1, 33_554_432);
    }

    function test_L01_hugePaymentSaturatesInsteadOfWrapping() public {
        // Even at the cap, a very large payment must push activeUntil forward,
        // never backwards past the timestamp.
        rto.openPlan(keccak256("longterm"), BUYER, ETH, USDC, address(0xC0FFEE), type(uint128).max, 1, 3650);
        rto.creditTransferLog(ETH, USDC, UNCLE, address(0xC0FFEE), type(uint128).max);
        assertTrue(rto.isActive(keccak256("longterm")), "still in the future");
    }

    // --- L-02: dust ---------------------------------------------------------

    function test_L02_smallPaymentsBuyRealTime() public {
        // Accrual in seconds rather than whole days. A payment worth less than
        // a day used to be recorded as money but buy nothing.
        uint128 dust = INSTALLMENT / 100; // 0.25 USDC of a 25 USDC installment
        assertTrue(rto.creditTransferLog(ETH, USDC, UNCLE, COLLECTOR, dust));
        assertGt(rto.timeRemaining(PLAN), 0, "buys time, not nothing");
        assertTrue(rto.isActive(PLAN));
    }

    // --- L-03: the zero plan id -------------------------------------------

    function test_L03_zeroPlanIdCannotBreakCollectorUniqueness() public {
        vm.expectRevert(RemitToOwn.BadTerms.selector);
        rto.openPlan(bytes32(0), BUYER, ETH, USDC, address(0xDEC0), PRICE, INSTALLMENT, DAYS_PER);
    }

    // --- accounting invariants (were already clean, kept as a guard) -------

    function testFuzz_paidNeverExceedsPriceAndNeverGoesBackwards(uint128 a, uint128 b, uint128 c) public {
        a = uint128(bound(a, 1, PRICE));
        b = uint128(bound(b, 1, PRICE));
        c = uint128(bound(c, 1, PRICE));

        rto.creditTransferLog(ETH, USDC, UNCLE, COLLECTOR, a);
        (,,,, uint128 p1,,,) = rto.getPlan(PLAN);
        rto.creditTransferLog(ETH, USDC, UNCLE, COLLECTOR, b);
        (,,,, uint128 p2,,,) = rto.getPlan(PLAN);
        rto.creditTransferLog(ETH, USDC, UNCLE, COLLECTOR, c);
        (,,,, uint128 p3,,, bool settled) = rto.getPlan(PLAN);

        assertLe(p3, PRICE, "never over the price");
        assertGe(p2, p1, "monotonic");
        assertGe(p3, p2, "monotonic");
        assertEq(rto.amountRemaining(PLAN), PRICE - p3, "remaining agrees");
        if (settled) assertEq(p3, PRICE);
    }
}
