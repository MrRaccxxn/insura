// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// Import ERC20 interface
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

/**
 * @title Insurance
 * @dev A smart contract for managing insurance policies, claims, and payouts
 */
contract Insurance {
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
        uint256 insuredAmount
    );
    event PolicyCancelled(uint256 policyId);
    event ClaimFiled(uint256 claimId, uint256 policyId, address claimant);
    event ClaimProcessed(uint256 claimId, ClaimStatus status);
    event ManagerAdded(address manager);
    event ManagerRemoved(address manager);
    event FundsWithdrawn(address to, uint256 amount);

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
     * @dev Create a new insurance policy
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
    ) external payable {
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
            payable(msg.sender).transfer(msg.value - premium);
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
            status: PolicyStatus.Active
        });

        // Track user's policies
        userPolicies[msg.sender].push(policyCounter);

        // Update total premium collected
        totalPremiumCollected += premium;

        emit PolicyCreated(policyCounter, msg.sender, premium, _insuredAmount);
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
    ) external onlyManager claimExists(_claimId) {
        Claim storage claim = claims[_claimId];
        Policy storage policy = policies[claim.policyId];

        require(
            claim.status == ClaimStatus.Pending,
            "Claim is already processed"
        );

        if (_approved) {
            // Check if contract has enough balance to pay the claim
            require(
                address(this).balance >= claim.claimAmount,
                "Insufficient contract balance for claim"
            );

            claim.status = ClaimStatus.Approved;
            policy.status = PolicyStatus.Claimed;

            // Make sure this transfer is working
            (bool success, ) = payable(claim.claimant).call{
                value: claim.claimAmount
            }("");
            require(success, "Claim payment failed");

            // Update total claims paid
            totalClaimsPaid += claim.claimAmount;
        } else {
            claim.status = ClaimStatus.Rejected;
        }

        emit ClaimProcessed(_claimId, claim.status);
    }

    /**
     * @dev Cancel an active policy
     * @param _policyId The ID of the policy to cancel
     */
    function cancelPolicy(uint256 _policyId) external policyExists(_policyId) {
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
            payable(msg.sender).transfer(refundAmount);
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
     * @dev Withdraw funds from the contract
     * @param _amount The amount to withdraw
     * @param _to The address to send funds to
     */
    function withdrawFunds(uint256 _amount, address _to) external onlyOwner {
        require(_amount > 0, "Amount must be greater than 0");
        require(_to != address(0), "Invalid address");
        require(
            _amount <= address(this).balance,
            "Insufficient contract balance"
        );

        payable(_to).transfer(_amount);
        emit FundsWithdrawn(_to, _amount);
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
            PolicyStatus status
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
            policy.status
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
     * @dev Get contract balance
     */
    function getContractBalance() external view onlyManager returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Extend policy duration
     * @param _policyId The ID of the policy to extend
     * @param _additionalDays Additional days to extend
     */
    function extendPolicy(
        uint256 _policyId,
        uint256 _additionalDays
    ) external payable policyExists(_policyId) {
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

        require(
            msg.value >= additionalPremium,
            "Insufficient payment for extension"
        );

        // Refund excess payment if any
        if (msg.value > additionalPremium) {
            payable(msg.sender).transfer(msg.value - additionalPremium);
        }

        // Update policy end date
        policy.endDate += _additionalDays * 1 days;

        // Update total premium collected
        totalPremiumCollected += additionalPremium;
    }

    /**
     * @dev Fallback function to accept Ether
     */
    receive() external payable {}

    /**
     * @dev Create a test claim
     * @param _id The ID of the claim
     * @param _policyId The ID of the policy
     * @param _claimant The address of the claimant
     * @param _claimAmount The amount of the claim
     * @param _filingDate The filing date of the claim
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
