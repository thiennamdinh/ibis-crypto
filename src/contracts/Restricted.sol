/**
 * Define functions and modifiers needed to implement controlled ownership of an
 * inheriting contract. This the Restricited class allows a multi-teired secure
 * ownership system that allows for single-owner approval, multi-owner approval,
 * and a limited number of last-resort operations by a "master" emergency
 * address.
 */

pragma solidity ^0.4.13;

/// Defines various access striction modifiers to be used by inheriting class
contract Restricted {

    uint256 MAX_UINT256 = 2**256-1;            // maximum unsigned integer value

    uint public numOwners;                     // number of owner addresses (excluding master)
    uint threshold;                            // number of owners needed to pass multiowner operation
    mapping(address => bool) public owners;    // flag registered owner addresses

    // (operation -> map) map operations to list of owners supporting it
    mapping(bytes32 => mapping(address => bool)) public supporting;
    mapping(bytes32 => uint) public numSupporting;   // number of owners approving an operation
    mapping(bytes32 => uint) public ownerInitTime;   // time a multiowner operaiton was initialized

    uint public delayDuration = 1000;                // amount of time an operation is delayed
    mapping(bytes32 => uint) public delayInitTime;   // time a delayed operation was initialized

    address masterAddress;                     // address for limited last-resort operations
    uint maxMasterOperations;                  // maximum number of uses of the master address
    uint usedMasterOperations;                 // operations executed by the master address so far
    bool masterSuspended;                      // flag signaling that master operation is underway
    bool ownersDestructed;                     // flag signaling that ownership notions are invalid

    // restricted events
    event LogOwnerChange(address indexed _addr, bool isOwner);
    event LogChangeThreshold(uint thresh);
    event LogChangeDelay(uint thresh);
    event LogMasterOperation();

    ///--------------------------------- Function Modifiers ---------------------------------///

    /// Function is only accessible to owners
    modifier isOwner() {
	require(owners[msg.sender] || ownersDestructed);
	_;
    }

    /// Function call must be approved by the stated threshold of owners
    modifier multiowner(bytes32 _operation) {
	if(!checkOwners(_operation)) {
	    assembly{stop}
	}
	_;
	delete ownerInitTime[_operation];
    }

    /// Function call will be delayed by a set time regardless of approval
    modifier delayed(bytes32 _operation) {
	if(!checkDelay(_operation)) {
	    assembly{stop}
	}
	_;
	delete delayInitTime[_operation];
    }

    /// Function can only be executed by the master address
    modifier isMaster() {
	if(!checkMaster()) {
	    assembly{stop}
	}
	_;
	usedMasterOperations++;
    }

    modifier suspendable() {
	require(!masterSuspended);
	_;
    }

    ///---------------------------------- Public Methods ------------------------------------///

    /// Constructor takes a list of owners and a threshold
    function Restricted(address[] _ownerList, uint _threshold, address _masterAddress) public {

	threshold = _threshold;
	LogChangeThreshold(threshold);

	masterAddress = _masterAddress;

	// add all given owners
	for(uint256 i = 0; i < _ownerList.length; i++) {
	    owners[_ownerList[i]] = true;
	    numOwners++;
	    LogOwnerChange(_ownerList[i], true);
	}
    }

    /// Add address to list of owners
    function addOwner(address _owner) public multiowner(keccak256(msg.data))
	delayed(keccak256(msg.data))
    {
	if(owners[_owner] == false){
	    owners[_owner] = true;
	    numOwners++;
	    LogOwnerChange(_owner, true);
	}
    }

    /// Remove address from list of owners
    function removeOwner(address _owner) public multiowner(keccak256(msg.data)) {
	owners[_owner] = false;
	numOwners--;
	LogOwnerChange(_owner, false);
    }

    /// Atomically swap out an owner address (avoids need to change thresholds)
    function switchOwner(address _old, address _new) public multiowner(keccak256(msg.data))
	delayed(keccak256(msg.data)) {

	owners[_old] = false;
	owners[_new] = true;

	LogOwnerChange(_old, false);
	LogOwnerChange(_new, true);
    }

    /// Instantly remove oneself as an owner (useful if a key has been compromised)
    function removeSelf() public isOwner {
	owners[msg.sender] = false;
	LogOwnerChange(msg.sender, false);
    }

    /// Change the min number of approving owners
    function changeThreshold(uint _threshold) public multiowner(keccak256(msg.data))
	delayed(keccak256(msg.data)) {

	threshold = _threshold;
	LogChangeThreshold(threshold);
    }

    /// Change the duration of the delay modifier
    function changeDelay(uint _delayDuration) public multiowner(keccak256(msg.data))
	delayed(keccak256(msg.data)) {
	delayDuration = _delayDuration;
	LogChangeDelay(delayDuration);
    }

    /// Cancel a currently delayed operation
    function killDelayed(bytes32 _operation) public multiowner(keccak256(msg.data)) {
	delete delayInitTime[_operation];
    }

    /// Allow an owner to revoke a previously approved call in a multi-owner vote
    function ownerRevoke(bytes32 _operation) public isOwner {
	supporting[_operation][msg.sender] = false;
	if(numSupporting[_operation] == 0) {
	    delete ownerInitTime[_operation];
	}
    }

    /// Cast vote for a multi-owner function call and return true if the call has been approved
    function checkOwners(bytes32 _operation) private returns (bool) {

	// if operation has already been approved then pass through
	if(ownerInitTime[_operation] != 0) {
	    return true;
	}

	// tally another owner vote
	if(owners[msg.sender] == true && supporting[_operation][msg.sender] == false) {
	    supporting[_operation][msg.sender] = true;
	    numSupporting[_operation]++;

	    // if enough owners have approved then continue execution
	    if(numSupporting[_operation] >= threshold) {
		ownerInitTime[_operation] = block.timestamp;
		return true;
	    }
	}
    }

    /// Check to see if the call has been sufficiently delayed and if so return true
    function checkDelay(bytes32 _operation) private returns (bool) {
	if(delayInitTime[_operation] == 0) {
	    delayInitTime[_operation] = block.timestamp;
	}

	return block.timestamp >= delayInitTime[_operation] + delayDuration;
    }

    /// Check to see if call came from the master address and there are operations remaining
    function checkMaster() public returns (bool) {
	masterSuspended = true;
	LogMasterOperation();
	return msg.sender == masterAddress && usedMasterOperations < maxMasterOperations;
    }

    /// Void all notions of ownership
    function RestrictedDestruct() internal {
	ownersDestructed = true;
	threshold = MAX_UINT256;
    }
}
