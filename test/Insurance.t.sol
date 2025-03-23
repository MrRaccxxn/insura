// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/Insurance.sol";

contract InsuranceTest is Test {
    Insurance insurance;
    address owner = address(0x1);
    address manager = address(0x2);
    address user1 = address(0x3);
    address user2 = address(0x4);

    // Setup function to deploy the contract before each test
    function setUp() public {
        vm.startPrank(owner);
        insurance = new Insurance();
        insurance.addManager(manager);
        vm.stopPrank();
    }

    // 1. DEPLOYMENT TESTS
    function testInitialState() public {
        assertEq(insurance.owner(), owner);
        assertTrue(insurance.managers(owner));
        assertTrue(insurance.managers(manager));
        assertEq(insurance.policyCounter(), 0);
        assertEq(insurance.claimCounter(), 0);
        assertEq(insurance.totalPremiumCollected(), 0);
        assertEq(insurance.totalClaimsPaid(), 0);
    }

    // 2. POLICY CREATION TESTS
    function testCreatePolicy() public {
        // Prepare policy parameters
        uint256 insuredAmount = 1000 ether;
        uint256 duration = 30; // 30 days
        uint8 riskLevel = 3; // Medium risk
        string memory data = "Sample policy data";

        // Calculate expected premium
        uint256 expectedPremium = insurance.calculatePremium(
            insuredAmount,
            duration,
            riskLevel
        );

        // Create policy from user1 account
        vm.startPrank(user1);
        vm.deal(user1, expectedPremium * 2); // Give user some ETH

        insurance.createPolicy{value: expectedPremium}(
            insuredAmount,
            duration,
            riskLevel,
            data
        );
        vm.stopPrank();

        // Verify policy creation
        assertEq(insurance.policyCounter(), 1);
        assertEq(insurance.totalPremiumCollected(), expectedPremium);

        // Check policy details
        (
            address insured,
            uint256 premium,
            uint256 insuredAmt,
            uint256 startDate,
            uint256 endDate,
            uint8 risk,
            string memory policyData,
            Insurance.PolicyStatus status
        ) = insurance.getPolicyDetails(1);

        assertEq(insured, user1);
        assertEq(premium, expectedPremium);
        assertEq(insuredAmt, insuredAmount);
        assertEq(risk, riskLevel);
        assertEq(policyData, data);
        assertTrue(endDate > startDate);
        assertEq(uint8(status), uint8(Insurance.PolicyStatus.Active));
    }

    function testPremiumCalculation() public {
        // Test different scenarios of premium calculation
        uint256 insuredAmount = 1000 ether;
        uint256 duration = 30;
        uint8 riskLevel = 3;

        uint256 premium = insurance.calculatePremium(
            insuredAmount,
            duration,
            riskLevel
        );
        // Premium should be: insuredAmount * duration * riskLevel / 10000
        uint256 expectedPremium = (insuredAmount * duration * riskLevel) /
            10000;
        assertEq(premium, expectedPremium);

        // Test high risk premium
        uint8 highRisk = 5;
        uint256 highRiskPremium = insurance.calculatePremium(
            insuredAmount,
            duration,
            highRisk
        );
        assertGt(highRiskPremium, premium);

        // Test low risk premium
        uint8 lowRisk = 1;
        uint256 lowRiskPremium = insurance.calculatePremium(
            insuredAmount,
            duration,
            lowRisk
        );
        assertLt(lowRiskPremium, premium);
    }

    function testPolicyCreationWithInsufficientFunds() public {
        uint256 insuredAmount = 1000 ether;
        uint256 duration = 30;
        uint8 riskLevel = 3;
        string memory data = "Sample policy data";

        uint256 expectedPremium = insurance.calculatePremium(
            insuredAmount,
            duration,
            riskLevel
        );
        uint256 insufficientAmount = expectedPremium / 2;

        vm.startPrank(user1);
        vm.deal(user1, insufficientAmount);

        vm.expectRevert("Insufficient premium amount");
        insurance.createPolicy{value: insufficientAmount}(
            insuredAmount,
            duration,
            riskLevel,
            data
        );
        vm.stopPrank();
    }

    function testPolicyCreationWithExcessPayment() public {
        uint256 insuredAmount = 1000 ether;
        uint256 duration = 30;
        uint8 riskLevel = 3;
        string memory data = "Sample policy data";

        uint256 expectedPremium = insurance.calculatePremium(
            insuredAmount,
            duration,
            riskLevel
        );
        uint256 excessAmount = expectedPremium * 2;

        vm.startPrank(user1);
        vm.deal(user1, excessAmount);

        uint256 initialBalance = user1.balance;
        insurance.createPolicy{value: excessAmount}(
            insuredAmount,
            duration,
            riskLevel,
            data
        );

        // Check refund of excess payment
        assertEq(user1.balance, initialBalance - expectedPremium);
        vm.stopPrank();
    }

    // 3. CLAIM FILING TESTS
    function testFileClaim() public {
        // First create a policy
        uint256 insuredAmount = 1000 ether;
        uint256 duration = 30;
        uint8 riskLevel = 3;
        string memory data = "Sample policy data";

        uint256 premium = insurance.calculatePremium(
            insuredAmount,
            duration,
            riskLevel
        );

        vm.startPrank(user1);
        vm.deal(user1, premium);
        insurance.createPolicy{value: premium}(
            insuredAmount,
            duration,
            riskLevel,
            data
        );

        // Now file a claim
        uint256 claimAmount = 500 ether;
        insurance.fileClaim(1, claimAmount);
        vm.stopPrank();

        // Verify claim creation
        assertEq(insurance.claimCounter(), 1);

        // Check claim details
        (
            uint256 policyId,
            address claimant,
            uint256 claimAmt,
            ,
            Insurance.ClaimStatus status
        ) = insurance.getClaimDetails(1);

        assertEq(policyId, 1);
        assertEq(claimant, user1);
        assertEq(claimAmt, claimAmount);
        assertEq(uint8(status), uint8(Insurance.ClaimStatus.Pending));
    }

    function testFileClaimWithExcessiveAmount() public {
        // Create policy
        createSamplePolicy(user1, 1000 ether, 30, 3);

        // Try to file a claim with amount higher than insured amount
        vm.prank(user1);
        vm.expectRevert("Claim amount exceeds insured amount");
        insurance.fileClaim(1, 1500 ether);
    }

    function testFileClaimOnExpiredPolicy() public {
        // Create policy
        createSamplePolicy(user1, 1000 ether, 30, 3);

        // Fast forward time beyond policy end date
        vm.warp(block.timestamp + 31 days);

        // Try to file a claim on expired policy
        vm.prank(user1);
        vm.expectRevert("Policy has expired");
        insurance.fileClaim(1, 500 ether);
    }

    function testFileClaimByNonOwner() public {
        // Create policy for user1
        createSamplePolicy(user1, 1000 ether, 30, 3);

        // Try to file a claim as user2
        vm.prank(user2);
        vm.expectRevert("Not the policy owner");
        insurance.fileClaim(1, 500 ether);
    }

    // 4. CLAIM PROCESSING TESTS
    function testApproveClaimByManager() public {
        // Create policy and file claim
        uint256 insuredAmount = 1000 ether;
        uint256 duration = 30;
        uint8 riskLevel = 3;
        uint256 claimAmount = 500 ether;

        // Calculate premium
        uint256 premium = insurance.calculatePremium(
            insuredAmount,
            duration,
            riskLevel
        );

        // Create policy for user1
        vm.startPrank(user1);
        vm.deal(user1, premium);
        insurance.createPolicy{value: premium}(
            insuredAmount,
            duration,
            riskLevel,
            "Sample policy"
        );

        // File a claim
        insurance.fileClaim(1, claimAmount);
        vm.stopPrank();

        // Reset user1 balance to clearly see the claim payment
        vm.deal(user1, 0);

        // IMPORTANT FIX: Directly fund the contract with enough ETH to cover the claim
        // This simulates the insurance company having capital reserves
        vm.deal(address(insurance), address(insurance).balance + claimAmount);

        // Process claim as manager
        vm.prank(manager);
        insurance.processClaim(1, true); // Approve claim

        // Verify claim is approved
        (, , , , Insurance.ClaimStatus status) = insurance.getClaimDetails(1);
        assertEq(uint8(status), uint8(Insurance.ClaimStatus.Approved));

        // Verify policy status is changed to Claimed
        (, , , , , , , Insurance.PolicyStatus policyStatus) = insurance
            .getPolicyDetails(1);
        assertEq(uint8(policyStatus), uint8(Insurance.PolicyStatus.Claimed));

        // Verify payment transferred to claimant
        assertEq(user1.balance, claimAmount);

        // Verify total claims paid increased
        assertEq(insurance.totalClaimsPaid(), claimAmount);
    }

    function testRejectClaimByManager() public {
        // Create policy and file claim
        createSamplePolicyAndClaim(user1, 1000 ether, 30, 3, 500 ether);

        // Process claim as manager - reject
        vm.prank(manager);
        insurance.processClaim(1, false);

        // Verify claim is rejected
        (, , , , Insurance.ClaimStatus status) = insurance.getClaimDetails(1);
        assertEq(uint8(status), uint8(Insurance.ClaimStatus.Rejected));

        // Verify policy status remains Active
        (, , , , , , , Insurance.PolicyStatus policyStatus) = insurance
            .getPolicyDetails(1);
        assertEq(uint8(policyStatus), uint8(Insurance.PolicyStatus.Active));
    }

    function testClaimProcessingByNonManager() public {
        // Create policy and file claim
        createSamplePolicyAndClaim(user1, 1000 ether, 30, 3, 500 ether);

        // Try to process claim as non-manager
        vm.prank(user2);
        vm.expectRevert("Only manager can call this function");
        insurance.processClaim(1, true);
    }

    function testProcessAlreadyProcessedClaim() public {
        // Calculate premium to ensure it's larger than claim amount
        uint256 insuredAmount = 1000 ether;
        uint256 duration = 30;
        uint8 riskLevel = 3;
        uint256 claimAmount = 500 ether;

        // Calculate premium
        uint256 premium = insurance.calculatePremium(
            insuredAmount,
            duration,
            riskLevel
        );

        // Ensure premium is sufficient or add extra funds
        if (premium < claimAmount) {
            // Add more funds to the contract
            vm.deal(address(insurance), claimAmount);
        }

        // Create policy and file claim
        createSamplePolicyAndClaim(
            user1,
            insuredAmount,
            duration,
            riskLevel,
            claimAmount
        );

        // Process claim first time
        vm.prank(manager);
        insurance.processClaim(1, true);

        // Try to process again
        vm.prank(manager);
        vm.expectRevert("Claim is already processed");
        insurance.processClaim(1, true);
    }

    // 5. POLICY CANCELLATION TESTS
    function testCancelPolicy() public {
        // Create policy
        uint256 premium = createSamplePolicy(user1, 1000 ether, 30, 3);

        // Initial user balance after policy creation
        uint256 initialUserBalance = user1.balance;

        // Wait 10 days
        vm.warp(block.timestamp + 10 days);

        // Cancel policy
        vm.prank(user1);
        insurance.cancelPolicy(1);

        // Verify policy status is Cancelled
        (, , , , , , , Insurance.PolicyStatus status) = insurance
            .getPolicyDetails(1);
        assertEq(uint8(status), uint8(Insurance.PolicyStatus.Cancelled));

        // Verify refund (should be ~60% of premium minus 10% cancellation fee)
        assertGt(user1.balance, initialUserBalance);
        assertLe(user1.balance - initialUserBalance, premium); // Refund less than original premium
    }

    function testCancelNonExistentPolicy() public {
        vm.prank(user1);
        vm.expectRevert("Policy does not exist");
        insurance.cancelPolicy(999);
    }

    function testCancelPolicyAsNonOwner() public {
        // Create policy for user1
        createSamplePolicy(user1, 1000 ether, 30, 3);

        // Try to cancel as user2
        vm.prank(user2);
        vm.expectRevert("Not the policy owner");
        insurance.cancelPolicy(1);
    }

    function testCancelAlreadyCancelledPolicy() public {
        // Create policy
        createSamplePolicy(user1, 1000 ether, 30, 3);

        // Cancel policy
        vm.prank(user1);
        insurance.cancelPolicy(1);

        // Try to cancel again
        vm.prank(user1);
        vm.expectRevert("Policy is not active");
        insurance.cancelPolicy(1);
    }

    // 6. POLICY EXTENSION TESTS
    function testExtendPolicy() public {
        // Create policy
        createSamplePolicy(user1, 1000 ether, 30, 3);

        // Get original end date
        (, , , , uint256 originalEndDate, , , ) = insurance.getPolicyDetails(1);

        // Calculate extension premium
        uint256 extensionDays = 15;
        uint256 extensionPremium = insurance.calculatePremium(
            1000 ether,
            extensionDays,
            3
        );

        // Extend policy
        vm.startPrank(user1);
        vm.deal(user1, extensionPremium);
        insurance.extendPolicy{value: extensionPremium}(1, extensionDays);
        vm.stopPrank();

        // Verify policy end date is extended
        (, , , , uint256 newEndDate, , , ) = insurance.getPolicyDetails(1);
        assertEq(newEndDate, originalEndDate + (extensionDays * 1 days));
    }

    function testExtendPolicyWithInsufficientPayment() public {
        // Create policy
        createSamplePolicy(user1, 1000 ether, 30, 3);

        // Calculate extension premium
        uint256 extensionDays = 15;
        uint256 extensionPremium = insurance.calculatePremium(
            1000 ether,
            extensionDays,
            3
        );

        // Try to extend with insufficient payment
        vm.startPrank(user1);
        vm.deal(user1, extensionPremium / 2);
        vm.expectRevert("Insufficient payment for extension");
        insurance.extendPolicy{value: extensionPremium / 2}(1, extensionDays);
        vm.stopPrank();
    }

    // 7. MANAGER ROLE TESTS
    function testAddManager() public {
        vm.startPrank(owner);
        insurance.addManager(user2);
        vm.stopPrank();

        assertTrue(insurance.managers(user2));
    }

    function testRemoveManager() public {
        // First add user2 as manager
        vm.prank(owner);
        insurance.addManager(user2);

        // Now remove
        vm.prank(owner);
        insurance.removeManager(user2);

        assertFalse(insurance.managers(user2));
    }

    function testAddManagerByNonOwner() public {
        vm.prank(user1);
        vm.expectRevert("Only owner can call this function");
        insurance.addManager(user2);
    }

    function testRemoveManagerByNonOwner() public {
        vm.prank(user1);
        vm.expectRevert("Only owner can call this function");
        insurance.removeManager(manager);
    }

    function testRemoveOwnerAsManager() public {
        vm.prank(owner);
        vm.expectRevert("Cannot remove owner as manager");
        insurance.removeManager(owner);
    }

    // 8. FUND WITHDRAWAL TESTS
    function testWithdrawFunds() public {
        // First add some funds by creating policies
        createSamplePolicy(user1, 1000 ether, 30, 3);
        createSamplePolicy(user2, 2000 ether, 60, 2);

        uint256 contractBalance = address(insurance).balance;
        uint256 withdrawAmount = contractBalance / 2;
        address withdrawRecipient = address(0x999);

        // Withdraw funds
        vm.prank(owner);
        insurance.withdrawFunds(withdrawAmount, withdrawRecipient);

        // Verify recipient received funds
        assertEq(withdrawRecipient.balance, withdrawAmount);

        // Verify contract balance reduced
        assertEq(address(insurance).balance, contractBalance - withdrawAmount);
    }

    function testWithdrawExcessFunds() public {
        // Add some funds
        createSamplePolicy(user1, 1000 ether, 30, 3);

        uint256 contractBalance = address(insurance).balance;
        uint256 excessAmount = contractBalance * 2;

        // Try to withdraw more than available
        vm.prank(owner);
        vm.expectRevert("Insufficient contract balance");
        insurance.withdrawFunds(excessAmount, user2);
    }

    function testWithdrawFundsByNonOwner() public {
        createSamplePolicy(user1, 1000 ether, 30, 3);

        vm.prank(user1);
        vm.expectRevert("Only owner can call this function");
        insurance.withdrawFunds(1 ether, user1);
    }

    // 9. EDGE CASE TESTS
    function testInsufficientContractBalanceForClaim() public {
        // Create policy with a small premium
        createSamplePolicy(user1, 1000 ether, 2, 1); // Very low premium

        // File claim for more than the premium paid
        uint256 claimAmount = 900 ether;
        vm.prank(user1);
        insurance.fileClaim(1, claimAmount);

        // Try to approve claim with insufficient contract balance
        vm.prank(manager);
        vm.expectRevert("Insufficient contract balance for claim");
        insurance.processClaim(1, true);
    }

    function testContractBalanceAfterMultipleOperations() public {
        // Start tracking balance
        uint256 initialBalance = address(insurance).balance;

        // Create policies
        uint256 premium1 = createSamplePolicy(user1, 1000 ether, 30, 3);
        uint256 premium2 = createSamplePolicy(user2, 2000 ether, 60, 2);

        // File and approve a claim
        uint256 claimAmount = 500 ether;
        vm.prank(user1);
        insurance.fileClaim(1, claimAmount);

        // IMPORTANT FIX: Add enough funds to the contract to cover the claim
        vm.deal(address(insurance), address(insurance).balance + claimAmount);

        vm.prank(manager);
        insurance.processClaim(1, true);

        // Cancel second policy after 20 days
        vm.warp(block.timestamp + 20 days);
        vm.prank(user2);
        insurance.cancelPolicy(2);

        // Final balance should be:
        // initial + premium1 + premium2 - claim1 - refund2
        uint256 finalBalance = address(insurance).balance;
        assertGt(finalBalance, initialBalance);
        assertLt(finalBalance, initialBalance + premium1 + premium2);
    }

    // 10. UTILITY FUNCTIONS FOR TESTING
    function createSamplePolicy(
        address policyHolder,
        uint256 insuredAmount,
        uint256 duration,
        uint8 riskLevel
    ) internal returns (uint256) {
        uint256 premium = insurance.calculatePremium(
            insuredAmount,
            duration,
            riskLevel
        );

        vm.startPrank(policyHolder);
        vm.deal(policyHolder, premium);
        insurance.createPolicy{value: premium}(
            insuredAmount,
            duration,
            riskLevel,
            "Sample policy data"
        );
        vm.stopPrank();

        return premium;
    }

    function createSamplePolicyAndClaim(
        address policyHolder,
        uint256 insuredAmount,
        uint256 duration,
        uint8 riskLevel,
        uint256 claimAmount
    ) internal {
        createSamplePolicy(policyHolder, insuredAmount, duration, riskLevel);

        vm.prank(policyHolder);
        insurance.fileClaim(1, claimAmount);

        // Ensure contract has enough funds to pay the claim
        vm.deal(address(insurance), address(insurance).balance + claimAmount);
    }
}
