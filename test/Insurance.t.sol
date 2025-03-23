// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/Insurance.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Create a simple mock token for testing
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        // Constructor is empty besides parent constructor call
    }

    // Function to mint tokens for testing
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract InsuranceTest is Test {
    Insurance insurance;
    MockToken mockToken;

    address owner = address(0x1);
    address manager = address(0x2);
    address user1 = address(0x3);
    address user2 = address(0x4);

    uint256 constant INITIAL_TOKEN_AMOUNT = 1000000 ether;

    // Setup function to deploy the contract before each test
    function setUp() public {
        vm.startPrank(owner);
        insurance = new Insurance();
        insurance.addManager(manager);

        // Deploy mock ERC20 token
        mockToken = new MockToken("Mock Token", "MTK");

        // Mint tokens to users for testing
        mockToken.mint(user1, INITIAL_TOKEN_AMOUNT);
        mockToken.mint(user2, INITIAL_TOKEN_AMOUNT);
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

    // 2. ETH POLICY CREATION TESTS
    function testCreateEthPolicy() public {
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

        // Check policy details - Split into multiple calls to reduce stack variables
        checkPolicyBasicDetails(1, user1, expectedPremium, insuredAmount);
        checkPolicyDates(1, duration);
        checkPolicyMetadata(1, riskLevel, data);
        checkPolicyStatusAndType(
            1,
            Insurance.PolicyStatus.Active,
            Insurance.AssetType.ETH,
            address(0)
        );
    }

    // Helper functions to verify policy details
    function checkPolicyBasicDetails(
        uint256 policyId,
        address expectedInsured,
        uint256 expectedPremium,
        uint256 expectedInsuredAmount
    ) internal {
        (
            address insured,
            uint256 premium,
            uint256 insuredAmount,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = insurance.getPolicyDetails(policyId);

        assertEq(insured, expectedInsured);
        assertEq(premium, expectedPremium);
        assertEq(insuredAmount, expectedInsuredAmount);
    }

    function checkPolicyDates(
        uint256 policyId,
        uint256 expectedDuration
    ) internal {
        (, , , uint256 startDate, uint256 endDate, , , , , ) = insurance
            .getPolicyDetails(policyId);

        assertTrue(endDate > startDate);
        assertApproxEqAbs(endDate - startDate, expectedDuration * 1 days, 5); // Allow small variance for block timing
    }

    function checkPolicyMetadata(
        uint256 policyId,
        uint8 expectedRiskLevel,
        string memory expectedData
    ) internal {
        (, , , , , uint8 riskLevel, string memory data, , , ) = insurance
            .getPolicyDetails(policyId);

        assertEq(riskLevel, expectedRiskLevel);
        assertEq(data, expectedData);
    }

    function checkPolicyStatusAndType(
        uint256 policyId,
        Insurance.PolicyStatus expectedStatus,
        Insurance.AssetType expectedType,
        address expectedToken
    ) internal {
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            Insurance.PolicyStatus status,
            Insurance.AssetType assetType,
            address tokenAddress
        ) = insurance.getPolicyDetails(policyId);

        assertEq(uint8(status), uint8(expectedStatus));
        assertEq(uint8(assetType), uint8(expectedType));
        assertEq(tokenAddress, expectedToken);
    }

    // 3. ERC20 POLICY CREATION TESTS
    function testCreateERC20Policy() public {
        // Prepare policy parameters
        uint256 insuredAmount = 1000 ether;
        uint256 duration = 30; // 30 days
        uint8 riskLevel = 3; // Medium risk
        string memory data = "Sample ERC20 policy data";

        // Calculate expected premium
        uint256 expectedPremium = insurance.calculatePremium(
            insuredAmount,
            duration,
            riskLevel
        );

        // Approve tokens for the insurance contract
        vm.startPrank(user1);
        mockToken.approve(address(insurance), expectedPremium);

        // Create ERC20 policy
        insurance.createERC20Policy(
            address(mockToken),
            insuredAmount,
            duration,
            riskLevel,
            data
        );
        vm.stopPrank();

        // Verify policy creation
        assertEq(insurance.policyCounter(), 1);
        assertEq(
            insurance.getTokenPremiumsCollected(address(mockToken)),
            expectedPremium
        );

        // Check policy details
        (
            address insured,
            uint256 premium,
            uint256 insuredAmt,
            uint256 startDate,
            uint256 endDate,
            uint8 risk,
            string memory policyData,
            Insurance.PolicyStatus status,
            Insurance.AssetType assetType,
            address tokenAddress
        ) = insurance.getPolicyDetails(1);

        assertEq(insured, user1);
        assertEq(premium, expectedPremium);
        assertEq(insuredAmt, insuredAmount);
        assertEq(risk, riskLevel);
        assertEq(policyData, data);
        assertTrue(endDate > startDate);
        assertEq(uint8(status), uint8(Insurance.PolicyStatus.Active));
        assertEq(uint8(assetType), uint8(Insurance.AssetType.ERC20));
        assertEq(tokenAddress, address(mockToken));

        // Verify token transfer
        assertEq(mockToken.balanceOf(address(insurance)), expectedPremium);
        assertEq(
            mockToken.balanceOf(user1),
            INITIAL_TOKEN_AMOUNT - expectedPremium
        );
    }

    function testERC20PolicyWithInsufficientAllowance() public {
        // Prepare policy parameters
        uint256 insuredAmount = 1000 ether;
        uint256 duration = 30;
        uint8 riskLevel = 3;
        string memory data = "Sample ERC20 policy data";

        uint256 expectedPremium = insurance.calculatePremium(
            insuredAmount,
            duration,
            riskLevel
        );
        uint256 insufficientAllowance = expectedPremium / 2;

        // Approve insufficient tokens
        vm.startPrank(user1);
        mockToken.approve(address(insurance), insufficientAllowance);

        // Attempt to create policy with insufficient allowance
        vm.expectRevert("Insufficient token allowance");
        insurance.createERC20Policy(
            address(mockToken),
            insuredAmount,
            duration,
            riskLevel,
            data
        );
        vm.stopPrank();
    }

    // 4. PREMIUM CALCULATION TESTS
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

    // 5. ETH POLICY CLAIM TESTS
    function testFileEthClaim() public {
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
            uint256 claimAmt, // Ignore filing date
            ,
            Insurance.ClaimStatus status
        ) = insurance.getClaimDetails(1);

        assertEq(policyId, 1);
        assertEq(claimant, user1);
        assertEq(claimAmt, claimAmount);
        assertEq(uint8(status), uint8(Insurance.ClaimStatus.Pending));
    }

    // 6. ERC20 POLICY CLAIM TESTS
    function testFileERC20Claim() public {
        // Create an ERC20 policy
        uint256 insuredAmount = 1000 ether;
        uint256 duration = 30;
        uint8 riskLevel = 3;
        string memory data = "Sample ERC20 policy data";

        uint256 premium = insurance.calculatePremium(
            insuredAmount,
            duration,
            riskLevel
        );

        vm.startPrank(user1);
        mockToken.approve(address(insurance), premium);
        insurance.createERC20Policy(
            address(mockToken),
            insuredAmount,
            duration,
            riskLevel,
            data
        );

        // File a claim
        uint256 claimAmount = 500 ether;
        insurance.fileClaim(1, claimAmount);
        vm.stopPrank();

        // Verify claim creation
        assertEq(insurance.claimCounter(), 1);

        // Check claim details
        (
            uint256 policyId,
            address claimant,
            uint256 claimAmt, // Ignore filing date
            ,
            Insurance.ClaimStatus status
        ) = insurance.getClaimDetails(1);

        assertEq(policyId, 1);
        assertEq(claimant, user1);
        assertEq(claimAmt, claimAmount);
        assertEq(uint8(status), uint8(Insurance.ClaimStatus.Pending));
    }

    // 7. ETH CLAIM PROCESSING TESTS
    function testApproveEthClaimByManager() public {
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

        // IMPORTANT: Add enough funds to the contract to cover the claim
        vm.deal(address(insurance), address(insurance).balance + claimAmount);

        // Process claim as manager
        vm.prank(manager);
        insurance.processClaim(1, true); // Approve claim

        // Verify claim is approved
        (, , , , Insurance.ClaimStatus status) = insurance.getClaimDetails(1);
        assertEq(uint8(status), uint8(Insurance.ClaimStatus.Approved));

        // Verify policy status is changed to Claimed
        (, , , , , , , Insurance.PolicyStatus policyStatus, , ) = insurance
            .getPolicyDetails(1);
        assertEq(uint8(policyStatus), uint8(Insurance.PolicyStatus.Claimed));

        // Verify payment transferred to claimant
        assertEq(user1.balance, claimAmount);

        // Verify total claims paid increased
        assertEq(insurance.totalClaimsPaid(), claimAmount);
    }

    // 8. ERC20 CLAIM PROCESSING TESTS
    function testApproveERC20ClaimByManager() public {
        // Create ERC20 policy and file claim
        uint256 insuredAmount = 1000 ether;
        uint256 duration = 30;
        uint8 riskLevel = 3;
        uint256 claimAmount = 500 ether;
        
        // Create policy for user1
        vm.startPrank(user1);
        mockToken.approve(address(insurance), insurance.calculatePremium(insuredAmount, duration, riskLevel));
        insurance.createERC20Policy(
            address(mockToken),
            insuredAmount,
            duration,
            riskLevel,
            "Sample ERC20 policy"
        );
        
        // File a claim
        insurance.fileClaim(1, claimAmount);
        vm.stopPrank();
        
        // Check user1's token balance before claim payment
        uint256 user1BalanceBefore = mockToken.balanceOf(user1);
        
        // IMPORTANT FIX: Fund contract with additional tokens to cover the claim
        // This simulates tokens from other policies or direct deposits
        vm.startPrank(owner);
        mockToken.mint(address(insurance), claimAmount); // Mint additional tokens to the contract
        vm.stopPrank();
        
        // Process claim as manager
        vm.prank(manager);
        insurance.processClaim(1, true); // Approve claim
        
        // Verify claim is approved
        (,,,, Insurance.ClaimStatus status) = insurance.getClaimDetails(1);
        assertEq(uint8(status), uint8(Insurance.ClaimStatus.Approved));
        
        // Verify policy status is changed to Claimed
        (,,,,,,,Insurance.PolicyStatus policyStatus,,) = insurance.getPolicyDetails(1);
        assertEq(uint8(policyStatus), uint8(Insurance.PolicyStatus.Claimed));
        
        // Verify tokens transferred to claimant
        assertEq(mockToken.balanceOf(user1), user1BalanceBefore + claimAmount);
        
        // Verify token claims paid increased
        assertEq(insurance.getTokenClaimsPaid(address(mockToken)), claimAmount);
    }

    // 9. POLICY CANCELLATION TESTS
    function testCancelEthPolicy() public {
        // Create ETH policy
        uint256 premium = createSampleEthPolicy(user1, 1000 ether, 30, 3);

        // Initial user balance after policy creation
        uint256 initialUserBalance = user1.balance;

        // Wait 10 days
        vm.warp(block.timestamp + 10 days);

        // Cancel policy
        vm.prank(user1);
        insurance.cancelPolicy(1);

        // Verify policy status is Cancelled
        (, , , , , , , Insurance.PolicyStatus status, , ) = insurance
            .getPolicyDetails(1);
        assertEq(uint8(status), uint8(Insurance.PolicyStatus.Cancelled));

        // Verify refund (should be ~60% of premium minus 10% cancellation fee)
        assertGt(user1.balance, initialUserBalance);
        assertLe(user1.balance - initialUserBalance, premium); // Refund less than original premium
    }

    function testCancelERC20Policy() public {
        // Create ERC20 policy
        uint256 premium = createSampleERC20Policy(user1, 1000 ether, 30, 3);

        // Initial user token balance after policy creation
        uint256 initialUserBalance = mockToken.balanceOf(user1);

        // Wait 10 days
        vm.warp(block.timestamp + 10 days);

        // Cancel policy
        vm.prank(user1);
        insurance.cancelPolicy(1);

        // Verify policy status is Cancelled
        (, , , , , , , Insurance.PolicyStatus status, , ) = insurance
            .getPolicyDetails(1);
        assertEq(uint8(status), uint8(Insurance.PolicyStatus.Cancelled));

        // Verify refund (should be ~60% of premium minus 10% cancellation fee)
        assertGt(mockToken.balanceOf(user1), initialUserBalance);
        assertLe(mockToken.balanceOf(user1) - initialUserBalance, premium); // Refund less than original premium
    }

    // 10. POLICY EXTENSION TESTS
    function testExtendEthPolicy() public {
        // Create ETH policy
        createSampleEthPolicy(user1, 1000 ether, 30, 3);

        // Get original end date
        (
            ,
            ,
            ,
            ,
            uint256 originalEndDate, // riskLevel
            // tokenAddress
            ,
            ,
            ,
            ,

        ) = insurance.getPolicyDetails(1);

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
        (
            ,
            ,
            ,
            ,
            uint256 newEndDate, // riskLevel
            // tokenAddress
            ,
            ,
            ,
            ,

        ) = // status
            // assetType
            insurance.getPolicyDetails(1);
        assertEq(newEndDate, originalEndDate + (extensionDays * 1 days));
    }

    function testExtendERC20Policy() public {
        // Create ERC20 policy
        createSampleERC20Policy(user1, 1000 ether, 30, 3);

        // Get original end date
        (
            ,
            ,
            ,
            ,
            uint256 originalEndDate, // riskLevel
            // status
            ,
            ,
            ,
            ,

        ) = // data
            // assetType
            insurance.getPolicyDetails(1);

        // Calculate extension premium
        uint256 extensionDays = 15;
        uint256 extensionPremium = insurance.calculatePremium(
            1000 ether,
            extensionDays,
            3
        );

        // Extend policy
        vm.startPrank(user1);
        mockToken.approve(address(insurance), extensionPremium);
        insurance.extendPolicy(1, extensionDays);
        vm.stopPrank();

        // Verify policy end date is extended
        (
            ,
            ,
            ,
            ,
            uint256 newEndDate, // riskLevel
            // status
            ,
            ,
            ,
            ,

        ) = // data
            // assetType
            insurance.getPolicyDetails(1);
        assertEq(newEndDate, originalEndDate + (extensionDays * 1 days));
    }

    // 11. WITHDRAWAL TESTS
    function testWithdrawEth() public {
        // Add ETH to contract
        createSampleEthPolicy(user1, 1000 ether, 30, 3);

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

    function testWithdrawTokens() public {
        // Add tokens to contract
        createSampleERC20Policy(user1, 1000 ether, 30, 3);

        uint256 contractTokenBalance = mockToken.balanceOf(address(insurance));
        uint256 withdrawAmount = contractTokenBalance / 2;
        address withdrawRecipient = address(0x999);

        // Withdraw tokens
        vm.prank(owner);
        insurance.withdrawTokens(
            address(mockToken),
            withdrawAmount,
            withdrawRecipient
        );

        // Verify recipient received tokens
        assertEq(mockToken.balanceOf(withdrawRecipient), withdrawAmount);

        // Verify contract token balance reduced
        assertEq(
            mockToken.balanceOf(address(insurance)),
            contractTokenBalance - withdrawAmount
        );
    }

    // 12. EDGE CASE TESTS
    function testInsufficientEthBalanceForClaim() public {
        // Create policy with a small premium
        createSampleEthPolicy(user1, 1000 ether, 2, 1); // Very low premium

        // File claim for more than the premium paid
        uint256 claimAmount = 900 ether;
        vm.prank(user1);
        insurance.fileClaim(1, claimAmount);

        // Try to approve claim with insufficient contract balance
        vm.prank(manager);
        vm.expectRevert("Insufficient contract balance for claim");
        insurance.processClaim(1, true);
    }

    function testInsufficientTokenBalanceForClaim() public {
        // Create policy with tokens
        createSampleERC20Policy(user1, 1000 ether, 2, 1); // Very low premium

        // File claim for more than the premium paid
        uint256 claimAmount = 900 ether;
        vm.prank(user1);
        insurance.fileClaim(1, claimAmount);

        // Try to approve claim with insufficient token balance
        vm.prank(manager);
        vm.expectRevert("Insufficient token balance for claim");
        insurance.processClaim(1, true);
    }

    function testMixedAssetsInContract() public {
        // Create ETH policy
        uint256 ethPremium = createSampleEthPolicy(user1, 1000 ether, 30, 3);
        
        // Create ERC20 policy
        uint256 tokenPremium = createSampleERC20Policy(user2, 2000 ether, 60, 2);
        
        // Check ETH and token balances
        assertEq(address(insurance).balance, ethPremium);
        assertEq(mockToken.balanceOf(address(insurance)), tokenPremium);
        
        // File ETH claim
        vm.prank(user1);
        insurance.fileClaim(1, 500 ether);
        
        // File token claim
        vm.prank(user2);
        insurance.fileClaim(2, 800 ether);
        
        // Add enough ETH to contract to cover claim
        vm.deal(address(insurance), address(insurance).balance + 500 ether);
        
        // IMPORTANT FIX: Add enough tokens to contract to cover the token claim
        vm.startPrank(owner);
        mockToken.mint(address(insurance), 800 ether - tokenPremium); // Only mint the difference needed
        vm.stopPrank();
        
        // Process ETH claim
        vm.prank(manager);
        insurance.processClaim(1, true);
        
        // Process token claim
        vm.prank(manager);
        insurance.processClaim(2, true);
        
        // Verify correct accounting
        assertEq(insurance.totalClaimsPaid(), 500 ether);
        assertEq(insurance.getTokenClaimsPaid(address(mockToken)), 800 ether);
    }

    // 13. UTILITY FUNCTIONS FOR TESTING
    function createSampleEthPolicy(
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
            "Sample ETH policy data"
        );
        vm.stopPrank();

        return premium;
    }

    function createSampleERC20Policy(
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
        mockToken.approve(address(insurance), premium);
        insurance.createERC20Policy(
            address(mockToken),
            insuredAmount,
            duration,
            riskLevel,
            "Sample ERC20 policy data"
        );
        vm.stopPrank();

        return premium;
    }

    function createSampleEthPolicyAndClaim(
        address policyHolder,
        uint256 insuredAmount,
        uint256 duration,
        uint8 riskLevel,
        uint256 claimAmount
    ) internal {
        createSampleEthPolicy(policyHolder, insuredAmount, duration, riskLevel);

        vm.prank(policyHolder);
        insurance.fileClaim(1, claimAmount);

        // Ensure contract has enough ETH to pay the claim
        vm.deal(address(insurance), address(insurance).balance + claimAmount);
    }

    function createSampleERC20PolicyAndClaim(
        address policyHolder,
        uint256 insuredAmount,
        uint256 duration,
        uint8 riskLevel,
        uint256 claimAmount
    ) internal {
        createSampleERC20Policy(policyHolder, insuredAmount, duration, riskLevel);
        
        vm.prank(policyHolder);
        insurance.fileClaim(1, claimAmount);
        
        // Ensure contract has enough tokens to pay the claim
        vm.startPrank(owner);
        uint256 currentBalance = mockToken.balanceOf(address(insurance));
        if (currentBalance < claimAmount) {
            mockToken.mint(address(insurance), claimAmount - currentBalance);
        }
        vm.stopPrank();
    }
}
