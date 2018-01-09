/**
 * Define primary business logic for the Ibis token. The module includes code
 * for handling standard user accounting (deposit/withdraw/transfer), mechanisms
 * for freezing and liquidiating rogue or lost accounts, and contract
 * upgrades. This contract inherits restricted access control and democratic
 * voting from parent contracts.
 */

pragma solidity ^0.4.13;

import "./ERC20.sol";
import "./ERC223.sol";
import "./Restricted.sol";
import "./Democratic.sol";
import "./Core.sol";

/// Implements the Ibis charity currency as an ERC20 token.
contract Ibis is ERC20, ERC223, Restricted, Democratic {

    // constant values
    uint MAX_UINT256 = 2**256-1;                 // maximum unsigned integer value
    uint constant MAJORITY = 50;                 // majority percentage (voting)
    uint constant SUPERMAJORITY = 67;            // supermajority percentage (voting)
    uint constant VOTE_DURATION = 1000;          // # of blocks per voting period
    uint constant MAX_NUKES = 3;                 // # of nukes available to nuke master

    // human standard token fields
    string public name = "Ibis";
    string public symbol = "IBI";
    string public version = '1.1';
    uint8 public decimals = 18;

    // address of core contract core
    Core public core;

    // address freezing/redistribution
    uint public awardMax = 1e18;                      // maximum award that can be claimed in one block
    uint public frozenMinTime = 1000;                 // min time between freezing and redistribution
    uint public awardMinTime = 1000;                  // min time to wait for charities to claim reward
    mapping(uint => uint) public awardValue;          // value of award at a given block
    mapping(uint => uint) public awardTarget;      // target address that would be closest
    mapping(uint => uint) public awardClosest;     // current winning bid for block award
    mapping(address => bool) public frozenVoted;      // votes cast by previously frozen accounts

    // initial grace period emergency update
    uint graceInit;
    uint graceDuration = 960 * 21;

    // if true then system has been nuked
    bool nuked;

    // business logic events
    event LogDeposit(address indexed _from, uint _value);
    event LogWithdraw(address indexed _to, uint _value);
    event LogChangeCharities(address indexed _charity, bool _isCharity);
    event LogFreeze(address indexed _account, bool frozen);
    event LogAward(uint indexed _time, address _addr, string _state);
    event LogUpgrade(address _addr);

    /// Define restricted ownership, voting parameters, and the Core contract
    function Ibis(address _core, address [] _owners, uint _ownerThreshold, address nukeMaster) public
	Restricted(_owners, _ownerThreshold, nukeMaster)
	Democratic(VOTE_DURATION, MAX_NUKES)
    {

	graceInit = block.timestamp;
	core = Core(_core);
    }

    ///-------------------------------- User Account Methods --------------------------------///

    // Return the balance of an address
    function balanceOf(address _owner) public constant returns (uint) {
	return core.balances(_owner);
    }

    /// Transfer value from the sending address to a given recipient
    function transfer(address _to, uint _value) public returns (bool) {
	if(core.balances(msg.sender) >= _value) {
	    core.transfer(msg.sender, _to, _value);

	    bytes memory empty;
	    Transfer(msg.sender, _to, _value);
	    Transfer(msg.sender, _to, _value, empty);
	    return true;
	}
    }

    function transfer(address _to, uint _value, bytes _data) public {
	if(core.balances(msg.sender) >= _value) {
	    // Retrieve the size of the code on target address
	    uint codeLength;
	    assembly {
	    codeLength := extcodesize(_to)
		    }

	    core.transfer(msg.sender, _to, _value);
	    if(codeLength>0) {
		ERC223ReceivingContract receiver = ERC223ReceivingContract(_to);
		receiver.tokenFallback(msg.sender, _value, _data);
	    }
	    Transfer(msg.sender, _to, _value, _data);
	}
    }

    /// Transfer value on behalf of another account if approved by the owner
    function transferFrom(address _from, address _to, uint _value) public returns (bool) {
        if(core.balances(_from) >= _value && core.allowed(_from, msg.sender) >= _value) {
	    core.transfer(_from, _to, _value);
	    core.setAllowed(_from, msg.sender, core.allowed(_from, msg.sender) - _value);
	    Transfer(_from, _to, _value);
	    return true;
	}
    }

    /// Convert Ether to Ibis coins for the message sender
    function deposit() public payable {
	depositTo(msg.sender);
    }

    /// Convert Ether to Ibis coins for an address other than the message sender
    function depositTo(address _to) public payable {
        core.setBalances(_to, core.balances(_to) + msg.value);
	totalSupply += msg.value;
	LogDeposit(_to, msg.value);
    }

    /// Convert Ibis coins to Ether for message sender
    function withdraw(uint _value) public suspendable returns (bool) {
	return withdrawHelper(msg.sender, _value);
    }

    /// Convert Ibis coins to Ether for someone other than message sender (requires pre-approval)
    function withdrawFrom(address _from, uint _value) public suspendable returns (bool) {
	if(core.allowed(_from, msg.sender) >= _value) {
	    return withdrawHelper(_from, _value);
	}
    }

    /// Convert Ibis coins to Ether on behalf of a charity by an Ibis owner address
    function withdrawOwner(address _from, uint _value) public isOwner suspendable returns (bool) {
	return withdrawHelper(_from, _value);
    }

    /// Internal logic for public withdraw interfaces
    function withdrawHelper(address _from, uint _value) public returns (bool) {
	if ((core.charityStatus(_from) || nuked) && _value <= core.balances(_from)) {
	    core.setBalances(_from, core.balances(_from) - _value);
	    totalSupply -= _value;
	    _from.transfer(_value);
	    LogWithdraw(_from, _value);
	    return true;
	}
    }

    /// Approve a third party address to manage funds on behalf of the owner
    function approve(address _spender, uint _value) public returns (bool) {
	core.setAllowed(msg.sender, _spender, _value);
	Approval(msg.sender, _spender, _value);
	return true;
    }

    /// Return the amount by which a third party is approved to transfer an owner's funds
    function allowance(address _owner, address _spender) public constant returns (uint) {
	return core.allowed(_owner, _spender);
    }

    /// Approve a third party to manange funds and callback a predesignated function signature
    function approveAndCall(address _spender, uint _value, bytes _extraCore) public returns (bool) {
        core.setAllowed(msg.sender, _spender, _value);
        Approval(msg.sender, _spender, _value);

        if(!_spender.call(bytes4(keccak256("receiveApproval(address,uint,address,bytes)")),
			  msg.sender, _value, this, _extraCore)) {
	    revert();
	}
        return true;
    }

    /// Approve a new charity
    function addCharity(address _charity) public isOwner delayed(keccak256(msg.data)) returns (bool) {
	if(!core.charityStatus(_charity)) {
	    core.setCharityStatus(_charity, true);
	    core.setCharityTime(_charity, block.timestamp);
	    LogChangeCharities(_charity, true);
	    return true;
	}
    }

    /// Remove an existing charity
    function removeCharity(address _charity) public isOwner delayed(keccak256(msg.data)) returns (bool) {
	if(core.charityStatus(_charity)) {
	    core.setCharityStatus(_charity, false);
	    core.setCharityTime(_charity, 0);
	    LogChangeCharities(_charity, false);
	    return true;
	}
    }

    ///---------------------------------- Freeze Methods ------------------------------------///

    /// Suspend accounts by moving the existing balance into a frozen funds table
    function freezeAccounts(address[] _accounts) public isOwner suspendable {
	for(uint i = 0; i < _accounts.length; i++) {
	    uint balance = core.balances(_accounts[i]);
	    core.setBalances(_accounts[i], 0);
	    core.setFrozenValue(_accounts[i], balance);
	    core.setFrozenTime(_accounts[i], block.timestamp);
	    LogFreeze(_accounts[i], true);
	}
    }

    /// Reinstantiate frozen accounts
    function unfreezeAccounts(address[] _accounts) public isOwner delayed(keccak256(msg.data))
	suspendable {
	for(uint i = 0; i < _accounts.length; i++) {
	    uint frozen = core.frozenValue(_accounts[i]);
	    core.setFrozenValue(_accounts[i], 0);
	    core.setFrozenTime(_accounts[i], 0);
	    core.setBalances(_accounts[i], frozen);
	    LogFreeze(_accounts[i], false);
	}
    }

    /// Liquidate frozen accounts and offer funds as reward for a randomly selected charity
    function awardExcess(address[] _accounts) public isOwner delayed(keccak256(msg.data))
	votable(keccak256(msg.data), MAJORITY, false) {
	uint frozenAward;

	for(uint i = 0; i < _accounts.length; i++) {
	    if(block.timestamp < core.frozenTime(_accounts[i]) + frozenMinTime) {
		continue;
	    }
	    uint frozen = core.frozenValue(_accounts[i]);
	    if(frozenAward + frozen <= awardMax) {
		core.setFrozenValue(_accounts[i], 0);
		frozenAward += frozen;
	    }
	    else {
		core.setFrozenValue(_accounts[i], frozen - (awardMax - frozenAward));
		frozenAward = awardMax;
		break;
	    }
	}

	// prepare reward slot
        awardValue[block.timestamp] = frozenAward;
	awardTarget[block.timestamp] = uint(block.blockhash(block.number));
	awardClosest[block.timestamp] = awardTarget[block.timestamp] + (MAX_UINT256 / 2);
	LogAward(block.timestamp, address(0), "initialized");
    }

    /// Claim that a charity is the closest to the random target for a given award
    function claimAward(uint _time, address _charity) public suspendable returns (bool) {

	uint challenge = uint(keccak256(_charity));

	if(awardTarget[_time] - uint(_charity) < awardTarget[_time] - awardClosest[_time]) {
	    awardClosest[_time] = challenge;
	    LogAward(_time, _charity, "claimed");
	    return true;
	}
    }

    /// Move funds into the balance of a winning charity after enough time has passed
    function cashAward(uint _time, address _charity) public suspendable returns (bool) {

	uint claim = uint(keccak256(_charity));

	if(_time <= block.timestamp - awardMinTime && awardClosest[_time] == claim) {
	    uint award = awardValue[_time];
	    delete awardValue[_time];
	    delete awardTarget[_time];
	    delete awardClosest[_time];
	    core.setBalances(_charity, core.balances(_charity) + award);
	    LogAward(_time, _charity, "awarded");
	    return true;
	}
    }

    /// Set the minimum time for an account to be frozen before distribution (block height)
    function setFrozenMinTime(uint _frozenMinTime) public multiowner(keccak256(msg.data))
	delayed(keccak256(msg.data)) {
	frozenMinTime = _frozenMinTime;
    }

    /// Set the window of time that charities can claim to be the closest to an award
    function setAwardMinTime(uint _awardMinTime) public multiowner(keccak256(msg.data))
	delayed(keccak256(msg.data)) {
	awardMinTime = _awardMinTime;
    }

    /// Set the maximum amount of funds that can be placed on a single block
    function setAwardMax(uint _awardMax) public multiowner(keccak256(msg.data))
	delayed(keccak256(msg.data)) {
	awardMax = _awardMax;
    }

    ///---------------------------------- Upgrade Methods -----------------------------------///

    /// Standard path to propose a new controlling contract
    function upgradeStandard(address _addr) public multiowner(keccak256(msg.data)) suspendable
	votable(keccak256(msg.data), MAJORITY, false) {
	upgrade(_addr);
    }

    /// Emergency path to upgrade contracts if majority owner keys have been compromised
    function upgradeEmergency(address _addr) public isOwner
	votable(keccak256(msg.data), SUPERMAJORITY, true) {
	upgrade(_addr);
    }

    /// Emergency path to upgrade if something has gone wrong within the grace period
    function upgradeInitial(address _addr) public isOwner() {
	if(graceInit + graceDuration < block.timestamp) {
	    upgrade(_addr);
	}
    }

    /// Perform actual upgrade
    function upgrade(address _addr) internal {
	if(IbisNew(_addr).init(totalSupply)) {
	    core.upgrade(_addr);
	    LogUpgrade(_addr);
	    selfdestruct(_addr);
	}
    }

    ///---------------------------------- Nuke Methods -----------------------------------///

    /// Supermajority vote to nuke the contract logic and allow free ether withdrawal
    function nuke() isMaster votable(keccak256(msg.data), SUPERMAJORITY, true) public {
	RestrictedDestruct();
	nuked = true;
    }

    ///------------------------------ Democratic Interface ------------------------------///

    mapping(address => uint) voteBalances;

    function purchaseVotes(address _addr, uint _votes) internal returns (uint) {
	if(_votes <= core.balances(_addr)){
	    voteBalances[_addr] += _votes;
	    core.setBalances(_addr, core.balances(_addr) - _votes);
	    return voteBalances[_addr] + core.frozenValue(_addr);
	}
    }

    function returnVotes(address _addr) internal {
	core.setBalances(_addr, core.balances(_addr) + voteBalances[_addr]);
	delete voteBalances[_addr];
    }

}

/// Abstract contract placeholder to facilitate a future transition to the next version of Ibis
contract IbisNew {
    /// This method will be implemented in the future contract version to process legacy data
    function init(uint totalSupply) public returns (bool);
}

contract ERC223ReceivingContract {
    function tokenFallback(address _from, uint _value, bytes _data) public;
}

/// for testing
contract IbisNewConcrete is IbisNew {
    function IbisNewConcrete(){}
    function init(uint) public returns (bool){return true;}
}
