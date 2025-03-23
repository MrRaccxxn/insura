// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Insurance
 * @dev A smart contract for managing insurance policies, claims, and payouts with support for ETH and ERC20 tokens
 */
contract Insurance is ReentrancyGuard {
    // Roles
    address public owner;
    mapping(address => bool) public managers;

    // Policy status enum
    enum PolicyStatus {
        Active,
        Expired,
        Claimed,
        Cancelled
    }

    // Claim status enum
    enum ClaimStatus {
        Pending,
        Approved,
        Rejected
    }

    // Asset type enum for policies
    enum AssetType {
        ETH,
        ERC20
    }

    // Policy struct to store policy details
    struct Policy {
        uint256 id;
        address insured;
        uint256 premium;
        uint256 insuredAmount;
        uint256 startDate;
        uint256 endDate;
        uint8 riskLevel; // 1-5, with 5 being highest risk
        string data; // Additional policy data (could be IPFS hash)
        PolicyStatus status;
        AssetType assetType;
        address tokenAddress; // Only used if assetType is ERC20
    }

    // Claim struct to store claim details
    struct Claim {
        uint256 id;
        uint256 policyId;
        address claimant;
        uint256 claimAmount;
        uint256 filingDate;
        ClaimStatus status;
    }

    // State variables
    uint256 public policyCounter;
    uint256 public claimCounter;
    uint256 public totalPremiumCollected;
    uint256 public totalClaimsPaid;

    // New state variables for token tracking
    mapping(address => uint256) public tokenPremiumsCollected;
    mapping(address => uint256) public tokenClaimsPaid;

    // Mappings
    mapping(uint256 => Policy) public policies;
    mapping(uint256 => Claim) public claims;
    mapping(address => uint256[]) public userPolicies;
    mapping(address => uint256[]) public userClaims;

    // Events
    event PolicyCreated(
        uint256 policyId,
        address insured,
        uint256 premium,
        uint256 insuredAmount,
        AssetType assetType,
        address tokenAddress
    );
    event PolicyCancelled(uint256 policyId);
    event ClaimFiled(uint256 claimId, uint256 policyId, address claimant);
    event ClaimProcessed(uint256 claimId, ClaimStatus status);
    event ManagerAdded(address manager);
    event ManagerRemoved(address manager);
    event FundsWithdrawn(address to, uint256 amount);
    event TokensWithdrawn(address tokenAddress, address to, uint256 amount);

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyManager() {
        require(
            managers[msg.sender] || msg.sender == owner,
            "Only manager can call this function"
        );
        _;
    }

    modifier policyExists(uint256 _policyId) {
        require(
            _policyId > 0 && _policyId <= policyCounter,
            "Policy does not exist"
        );
        _;
    }

    modifier claimExists(uint256 _claimId) {
        require(
            _claimId > 0 && _claimId <= claimCounter,
            "Claim does not exist"
        );
        _;
    }

    constructor() {
        owner = msg.sender;
        managers[msg.sender] = true;
    }

    /**
     * @dev Create a new insurance policy with ETH
     * @param _insuredAmount The amount to be insured
     * @param _duration Duration of policy in days
     * @param _riskLevel Risk level of the policy (1-5)
     * @param _data Additional policy data
     */
    function createPolicy(
        uint256 _insuredAmount,
        uint256 _duration,
        uint8 _riskLevel,
        string memory _data
    ) external payable nonReentrant {
        require(_insuredAmount > 0, "Insured amount must be greater than 0");
        require(_duration > 0, "Duration must be greater than 0");
        require(
            _riskLevel >= 1 && _riskLevel <= 5,
            "Risk level must be between 1 and 5"
        );

        // Calculate premium based on insured amount, duration, and risk level
        uint256 premium = calculatePremium(
            _insuredAmount,
            _duration,
            _riskLevel
        );
        require(msg.value >= premium, "Insufficient premium amount");

        // Refund excess payment if any
        if (msg.value > premium) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - premium}("");
            require(success, "Refund transfer failed");
        }

        // Update policy counter
        policyCounter++;

        // Create new policy
        policies[policyCounter] = Policy({
            id: policyCounter,
            insured: msg.sender,
            premium: premium,
            insuredAmount: _insuredAmount,
            startDate: block.timestamp,
            endDate: block.timestamp + (_duration * 1 days),
            riskLevel: _riskLevel,
            data: _data,
            status: PolicyStatus.Active,
            assetType: AssetType.ETH,
            tokenAddress: address(0)
        });

        // Track user's policies
        userPolicies[msg.sender].push(policyCounter);

        // Update total premium collected
        totalPremiumCollected += premium;

        emit PolicyCreated(
            policyCounter,
            msg.sender,
            premium,
            _insuredAmount,
            AssetType.ETH,
            address(0)
        );
    }

    /**
     * @dev Create a new insurance policy with ERC20 token
     * @param _tokenAddress The address of the ERC20 token
     * @param _insuredAmount The amount to be insured
     * @param _duration Duration of policy in days
     * @param _riskLevel Risk level of the policy (1-5)
     * @param _data Additional policy data
     */
    function createERC20Policy(
        address _tokenAddress,
        uint256 _insuredAmount,
        uint256 _duration,
        uint8 _riskLevel,
        string memory _data
    ) external nonReentrant {
        require(_tokenAddress != address(0), "Token address cannot be zero");
        require(_insuredAmount > 0, "Insured amount must be greater than 0");
        require(_duration > 0, "Duration must be greater than 0");
        require(
            _riskLevel >= 1 && _riskLevel <= 5,
            "Risk level must be between 1 and 5"
        );

        // Calculate premium based on insured amount, duration, and risk level
        uint256 premium = calculatePremium(
            _insuredAmount,
            _duration,
            _riskLevel
        );

        // Get token interface
        IERC20 token = IERC20(_tokenAddress);

        // Ensure the contract has enough allowance
        require(
            token.allowance(msg.sender, address(this)) >= premium,
            "Insufficient token allowance"
        );

        // Transfer premium from user to contract
        bool success = token.transferFrom(msg.sender, address(this), premium);
        require(success, "Token transfer failed");

        // Update policy counter
        policyCounter++;

        // Create new policy
        policies[policyCounter] = Policy({
            id: policyCounter,
            insured: msg.sender,
            premium: premium,
            insuredAmount: _insuredAmount,
            startDate: block.timestamp,
            endDate: block.timestamp + (_duration * 1 days),
            riskLevel: _riskLevel,
            data: _data,
            status: PolicyStatus.Active,
            assetType: AssetType.ERC20,
            tokenAddress: _tokenAddress
        });

        // Track user's policies
        userPolicies[msg.sender].push(policyCounter);

        // Update token premium collected
        tokenPremiumsCollected[_tokenAddress] += premium;

        emit PolicyCreated(
            policyCounter,
            msg.sender,
            premium,
            _insuredAmount,
            AssetType.ERC20,
            _tokenAddress
        );
    }

    /**
     * @dev Calculate premium amount based on policy parameters
     */
    function calculatePremium(
        uint256 _insuredAmount,
        uint256 _duration,
        uint8 _riskLevel
    ) public pure returns (uint256) {
        // Simple premium calculation: insuredAmount * duration(days) * riskLevel / 10000
        // Higher risk level means higher premium
        return (_insuredAmount * _duration * _riskLevel) / 10000;
    }

    /**
     * @dev File an insurance claim
     * @param _policyId The ID of the policy being claimed
     * @param _claimAmount The amount being claimed
     */
    function fileClaim(
        uint256 _policyId,
        uint256 _claimAmount
    ) external policyExists(_policyId) {
        Policy storage policy = policies[_policyId];

        require(policy.insured == msg.sender, "Not the policy owner");
        require(policy.status == PolicyStatus.Active, "Policy is not active");
        require(block.timestamp <= policy.endDate, "Policy has expired");
        require(
            _claimAmount <= policy.insuredAmount,
            "Claim amount exceeds insured amount"
        );

        // Create new claim
        claimCounter++;

        claims[claimCounter] = Claim({
            id: claimCounter,
            policyId: _policyId,
            claimant: msg.sender,
            claimAmount: _claimAmount,
            filingDate: block.timestamp,
            status: ClaimStatus.Pending
        });

        // Track user's claims
        userClaims[msg.sender].push(claimCounter);

        emit ClaimFiled(claimCounter, _policyId, msg.sender);
    }

    /**
     * @dev Process a claim (approve or reject)
     * @param _claimId The ID of the claim to process
     * @param _approved Whether the claim is approved
     */
    function processClaim(
        uint256 _claimId,
        bool _approved
    ) external onlyManager claimExists(_claimId) nonReentrant {
        Claim storage claim = claims[_claimId];
        Policy storage policy = policies[claim.policyId];

        require(
            claim.status == ClaimStatus.Pending,
            "Claim is already processed"
        );

        if (_approved) {
            claim.status = ClaimStatus.Approved;
            policy.status = PolicyStatus.Claimed;

            // Handle payment based on asset type
            if (policy.assetType == AssetType.ETH) {
                // Check if contract has enough ETH balance
                require(
                    address(this).balance >= claim.claimAmount,
                    "Insufficient contract balance for claim"
                );

                // Make ETH payment
                (bool success, ) = payable(claim.claimant).call{
                    value: claim.claimAmount
                }("");
                require(success, "ETH payment failed");

                // Update total claims paid for ETH
                totalClaimsPaid += claim.claimAmount;
            } else {
                // This is an ERC20 token claim
                IERC20 token = IERC20(policy.tokenAddress);

                // Check if contract has enough token balance
                require(
                    token.balanceOf(address(this)) >= claim.claimAmount,
                    "Insufficient token balance for claim"
                );

                // Make token payment
                bool success = token.transfer(
                    claim.claimant,
                    claim.claimAmount
                );
                require(success, "Token payment failed");

                // Update token claims paid
                tokenClaimsPaid[policy.tokenAddress] += claim.claimAmount;
            }
        } else {
            claim.status = ClaimStatus.Rejected;
        }

        emit ClaimProcessed(_claimId, claim.status);
    }

    /**
     * @dev Cancel an active policy
     * @param _policyId The ID of the policy to cancel
     */
    function cancelPolicy(
        uint256 _policyId
    ) external policyExists(_policyId) nonReentrant {
        Policy storage policy = policies[_policyId];

        require(policy.insured == msg.sender, "Not the policy owner");
        require(policy.status == PolicyStatus.Active, "Policy is not active");

        policy.status = PolicyStatus.Cancelled;

        // Calculate refund amount based on remaining policy duration
        uint256 elapsedTime = block.timestamp - policy.startDate;
        uint256 totalDuration = policy.endDate - policy.startDate;
        uint256 remainingDuration = totalDuration > elapsedTime
            ? totalDuration - elapsedTime
            : 0;

        // Refund proportional to remaining time (minus a cancellation fee of 10%)
        if (remainingDuration > 0) {
            uint256 refundAmount = (policy.premium * remainingDuration * 90) /
                (totalDuration * 100);

            // Process refund based on asset type
            if (policy.assetType == AssetType.ETH) {
                (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
                require(success, "ETH refund failed");
            } else {
                IERC20 token = IERC20(policy.tokenAddress);
                bool success = token.transfer(msg.sender, refundAmount);
                require(success, "Token refund failed");
            }
        }

        emit PolicyCancelled(_policyId);
    }

    /**
     * @dev Add a manager
     * @param _manager Address of the manager to add
     */
    function addManager(address _manager) external onlyOwner {
        require(_manager != address(0), "Invalid address");
        require(!managers[_manager], "Already a manager");

        managers[_manager] = true;
        emit ManagerAdded(_manager);
    }

    /**
     * @dev Remove a manager
     * @param _manager Address of the manager to remove
     */
    function removeManager(address _manager) external onlyOwner {
        require(managers[_manager], "Not a manager");
        require(_manager != owner, "Cannot remove owner as manager");

        managers[_manager] = false;
        emit ManagerRemoved(_manager);
    }

    /**
     * @dev Withdraw ETH from the contract
     * @param _amount The amount to withdraw
     * @param _to The address to send funds to
     */
    function withdrawFunds(
        uint256 _amount,
        address _to
    ) external onlyOwner nonReentrant {
        require(_amount > 0, "Amount must be greater than 0");
        require(_to != address(0), "Invalid address");
        require(
            _amount <= address(this).balance,
            "Insufficient contract balance"
        );

        (bool success, ) = payable(_to).call{value: _amount}("");
        require(success, "ETH withdrawal failed");
        emit FundsWithdrawn(_to, _amount);
    }

    /**
     * @dev Withdraw ERC20 tokens from the contract
     * @param _tokenAddress The address of the token
     * @param _amount The amount of tokens to withdraw
     * @param _to The address to send tokens to
     */
    function withdrawTokens(
        address _tokenAddress,
        uint256 _amount,
        address _to
    ) external onlyOwner nonReentrant {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_amount > 0, "Amount must be greater than 0");
        require(_to != address(0), "Invalid address");

        IERC20 token = IERC20(_tokenAddress);
        require(
            token.balanceOf(address(this)) >= _amount,
            "Insufficient token balance"
        );

        bool success = token.transfer(_to, _amount);
        require(success, "Token transfer failed");

        emit TokensWithdrawn(_tokenAddress, _to, _amount);
    }

    /**
     * @dev Get user policies
     * @param _user Address of the user
     */
    function getUserPolicies(
        address _user
    ) external view returns (uint256[] memory) {
        return userPolicies[_user];
    }

    /**
     * @dev Get user claims
     * @param _user Address of the user
     */
    function getUserClaims(
        address _user
    ) external view returns (uint256[] memory) {
        return userClaims[_user];
    }

    /**
     * @dev Get policy details
     * @param _policyId The ID of the policy
     */
    function getPolicyDetails(
        uint256 _policyId
    )
        external
        view
        policyExists(_policyId)
        returns (
            address insured,
            uint256 premium,
            uint256 insuredAmount,
            uint256 startDate,
            uint256 endDate,
            uint8 riskLevel,
            string memory data,
            PolicyStatus status,
            AssetType assetType,
            address tokenAddress
        )
    {
        Policy storage policy = policies[_policyId];
        return (
            policy.insured,
            policy.premium,
            policy.insuredAmount,
            policy.startDate,
            policy.endDate,
            policy.riskLevel,
            policy.data,
            policy.status,
            policy.assetType,
            policy.tokenAddress
        );
    }

    /**
     * @dev Get claim details
     * @param _claimId The ID of the claim
     */
    function getClaimDetails(
        uint256 _claimId
    )
        external
        view
        claimExists(_claimId)
        returns (
            uint256 policyId,
            address claimant,
            uint256 claimAmount,
            uint256 filingDate,
            ClaimStatus status
        )
    {
        Claim storage claim = claims[_claimId];
        return (
            claim.policyId,
            claim.claimant,
            claim.claimAmount,
            claim.filingDate,
            claim.status
        );
    }

    /**
     * @dev Get contract ETH balance
     */
    function getContractBalance() external view onlyManager returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Get contract token balance
     * @param _tokenAddress The address of the token
     */
    function getContractTokenBalance(
        address _tokenAddress
    ) external view onlyManager returns (uint256) {
        require(_tokenAddress != address(0), "Invalid token address");
        IERC20 token = IERC20(_tokenAddress);
        return token.balanceOf(address(this));
    }

    /**
     * @dev Get token premiums collected
     * @param _tokenAddress The address of the token
     */
    function getTokenPremiumsCollected(
        address _tokenAddress
    ) external view returns (uint256) {
        return tokenPremiumsCollected[_tokenAddress];
    }

    /**
     * @dev Get token claims paid
     * @param _tokenAddress The address of the token
     */
    function getTokenClaimsPaid(
        address _tokenAddress
    ) external view returns (uint256) {
        return tokenClaimsPaid[_tokenAddress];
    }

    /**
     * @dev Extend policy duration
     * @param _policyId The ID of the policy to extend
     * @param _additionalDays Additional days to extend
     */
    function extendPolicy(
        uint256 _policyId,
        uint256 _additionalDays
    ) external payable policyExists(_policyId) nonReentrant {
        require(_additionalDays > 0, "Additional days must be greater than 0");

        Policy storage policy = policies[_policyId];
        require(policy.insured == msg.sender, "Not the policy owner");
        require(policy.status == PolicyStatus.Active, "Policy is not active");

        // Calculate additional premium
        uint256 additionalPremium = calculatePremium(
            policy.insuredAmount,
            _additionalDays,
            policy.riskLevel
        );

        // Handle payment based on asset type
        if (policy.assetType == AssetType.ETH) {
            require(
                msg.value >= additionalPremium,
                "Insufficient payment for extension"
            );

            // Refund excess payment if any
            (bool success, ) = payable(msg.sender).call{value: msg.value - additionalPremium}("");
            require(success, "Refund transfer failed");

            // Update total premium collected for ETH
            totalPremiumCollected += additionalPremium;
        } else {
            // This is an ERC20 policy extension
            IERC20 token = IERC20(policy.tokenAddress);

            // Check allowance
            require(
                token.allowance(msg.sender, address(this)) >= additionalPremium,
                "Insufficient token allowance"
            );

            // Transfer additional premium
            bool success = token.transferFrom(
                msg.sender,
                address(this),
                additionalPremium
            );
            require(success, "Token transfer failed");

            // Update token premium collected
            tokenPremiumsCollected[policy.tokenAddress] += additionalPremium;
        }

        // Update policy end date
        policy.endDate += _additionalDays * 1 days;
    }

    /**
     * @dev Fallback function to accept Ether
     */
    receive() external payable {}

    /**
     * @dev Create a test claim (for testing purposes only)
     */
    function createTestClaim(
        uint256 _id,
        uint256 _policyId,
        address _claimant,
        uint256 _claimAmount,
        uint256 _filingDate
    ) external onlyOwner {
        claims[_id] = Claim({
            id: _id,
            policyId: _policyId,
            claimant: _claimant,
            claimAmount: _claimAmount,
            filingDate: _filingDate,
            status: ClaimStatus.Pending
        });

        if (_id > claimCounter) {
            claimCounter = _id;
        }
    }
}
