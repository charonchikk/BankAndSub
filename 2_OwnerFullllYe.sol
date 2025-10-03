// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.2 <0.9.0;

contract Bank {
    address public owner;
    mapping(address => address) public subscriberOf;  
    mapping(address => bool) public isActive;
    mapping(address => string) public nameOf;
    uint256 public totalAllocated;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner call this function!");
        _;
    }

    event SubscriberCreated(address indexed wallet, address indexed subscriber, string name);
    event SubscriberDeactivated(address indexed wallet);
    event SubscriberReactivated(address indexed wallet);
    event Deposited(address indexed wallet, uint256 amount);
    event Staked(address indexed wallet, uint256 amount);
    event Unstaked(address indexed wallet, uint256 amount);
    event BankToppedUp(address indexed by, uint256 amount);
    event BankWithdrawn(address indexed to, uint256 amount);

    function createSubscriber(address wallet, string calldata name_) external onlyOwner returns(address subscriber) {
        require(wallet != address(0), "Wallet cannot be zero address");
        require(subscriberOf[wallet] == address(0), "Subscriber already exists for this wallet");

        subscriber = address(new Subscriber(address(this), wallet, name_));

        subscriberOf[wallet] = subscriber;  
        nameOf[wallet] = name_;
        isActive[wallet] = true;

        emit SubscriberCreated(wallet, subscriber, name_);
    }

    function deactivateSubscriber(address wallet) external onlyOwner {
        require(subscriberOf[wallet] != address(0), "Subscriber does not exist");
        require(isActive[wallet], "Subscriber is already inactive");

        isActive[wallet] = false;
        Subscriber(subscriberOf[wallet]).onBankDeactivate();  
        emit SubscriberDeactivated(wallet);
    }

    function reactivateSubscriber(address wallet) external onlyOwner {
        require(subscriberOf[wallet] != address(0), "Subscriber does not exist");
        require(!isActive[wallet], "Subscriber is already active");

        isActive[wallet] = true;
        emit SubscriberReactivated(wallet);
    }

    function getSubscriber(address wallet) external view returns (address) {
        return subscriberOf[wallet];
    }

    function getSubscriberName(address wallet) external view returns(string memory) {
        require(subscriberOf[wallet] != address(0), "Subscriber does not exist");
        return nameOf[wallet];
    }

    function depositFor(address wallet) external payable {
        require(msg.value > 0, "deposit amount must positive");
        require(subscriberOf[wallet] != address(0), "subscriber does not exist");
        require(isActive[wallet], "subscriber is not active");

        totalAllocated += msg.value;
        Subscriber(subscriberOf[wallet]).onBankDeposit(msg.value);

        require(address(this).balance >= totalAllocated, "Bank invariant violated"); 
        emit Deposited(wallet, msg.value);
    }

    function stakeFromSubscriber(address wallet, uint256 amount) external {
        require(isActive[wallet], "subscriber is not active");
        require(amount > 0, "Amount must be positive");
        require(msg.sender == subscriberOf[wallet], "Only subscriber contract can call this");

        Subscriber(subscriberOf[wallet]).onBankStake(amount);
        emit Staked(wallet, amount);
    }

    function unstakeFromSubscriber(address wallet, uint256 amount) external {
        require(isActive[wallet], "Subscriber is not active");
        require(amount > 0, "Amount must be positive");
        require(msg.sender == subscriberOf[wallet], "Only subscriber contract can call this");

        Subscriber(subscriberOf[wallet]).onBankUnstake(amount);
        emit Unstaked(wallet, amount);
    }

    function topUpBank() external payable onlyOwner {
        emit BankToppedUp(msg.sender, msg.value);
    }

    function withdrawBank(uint256 amount, address payable to) external onlyOwner {
        require(to != address(0), "cannot withdraw to zero address");
        require(amount > 0, "Amount must be positive");
        require(address(this).balance - amount >= totalAllocated, "Cannot withdraw allocated fund");

        to.transfer(amount);
        emit BankWithdrawn(to, amount);
    }
}

contract Subscriber {
    address public immutable bank;
    address public immutable wallet;
    string public name;

    struct Ledger {
        uint128 available;
        uint128 staked;
        uint128 totalDeposited;
        uint128 totalStaked;
        uint64 createdAt;
        uint64 lastUpdate;
        uint64 deactivatedAt;
    }

    Ledger public ledger;

    event StakeRequested(uint256 amount);
    event UnstakeRequested(uint256 amount);  
    event LedgerUpdated(uint128 available, uint128 staked);
    event Deactivated();

    constructor(address bank_, address wallet_, string memory name_) {
        bank = bank_;
        wallet = wallet_;
        name = name_;
        ledger = Ledger({  
            available: 0,
            staked: 0,
            totalDeposited: 0,
            totalStaked: 0,
            createdAt: uint64(block.timestamp),  
            lastUpdate: uint64(block.timestamp),  
            deactivatedAt: 0  
        });  
    }

    function stake(uint256 amount) external {
        require(msg.sender == wallet, "only wallet owner can stake");
        require(amount > 0, "amount must be positive");

        emit StakeRequested(amount);  
        Bank(bank).stakeFromSubscriber(wallet, amount);
        ledger.lastUpdate = uint64(block.timestamp);  
    }

    function unstake(uint256 amount) external { 
        require(msg.sender == wallet, "only wallet owner can unstake");
        require(amount > 0, "amount must be positive");

        emit UnstakeRequested(amount);
        Bank(bank).unstakeFromSubscriber(wallet, amount);
        ledger.lastUpdate = uint64(block.timestamp);
    }

    function getLedger() external view returns (Ledger memory) {  
        return ledger;
    }

    function onBankDeposit(uint256 amount) external onlyBank {
        ledger.available += uint128(amount);
        ledger.totalDeposited += uint128(amount);
        ledger.lastUpdate = uint64(block.timestamp);
        emit LedgerUpdated(ledger.available, ledger.staked);
    }

    function onBankStake(uint256 amount) external onlyBank {
        require(ledger.available >= amount, "Insufficient available balance");
        ledger.available -= uint128(amount);
        ledger.staked += uint128(amount);
        ledger.totalStaked += uint128(amount);
        ledger.lastUpdate = uint64(block.timestamp);
        emit LedgerUpdated(ledger.available, ledger.staked);
    }

    function onBankUnstake(uint256 amount) external onlyBank {  
        require(ledger.staked >= amount, "Insufficient staked balance");
        ledger.staked -= uint128(amount);
        ledger.available += uint128(amount);
        ledger.lastUpdate = uint64(block.timestamp);
        emit LedgerUpdated(ledger.available, ledger.staked);
    }

    function onBankDeactivate() external onlyBank {
        ledger.deactivatedAt = uint64(block.timestamp);
        emit Deactivated();
    }

    modifier onlyBank() {
        require(msg.sender == bank, "only bank can call this");
        _;
    }
}