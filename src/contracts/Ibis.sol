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
    uint constant SUPERMAJORITY = 75;            // supermajority percentage (voting)
    uint constant VOTE_DURATION = 1000;          // # of blocks per voting period
    uint constant MAX_NUKES = 3;                 // # of nukes available to nuke master

    // human standard token fields
    string public name = "Ibis";
    string public symbol = "IBIS";
    string public version = '1.1';
    uint8 public decimals = 18;

    // address of Core contract storing user data
    Core public core;

    // address freezing/redistribution state
    uint public awardMax = 1e18;                      // maximum amount to be claimed in one award
    uint public frozenMinTime = 10000;                // min time between freezing and redistribution
    uint public awardMinTime = 10000;                 // min time to wait for charities to claim reward
    mapping(uint => uint) public awardValue;          // (time->tokens) value of a single award
    mapping(uint => uint) public awardBlock;          // (time->block) used to set the target
    mapping(uint => uint) public awardRand;           // (time->hash) randomness used to select winner
    mapping(uint => uint) public awardClosest;        // (time->hash) closest charity so far

    mapping(address => bool) public frozenVoted;      // votes cast by frozen accounts

    uint graceInit;                                   // initial time of contract launch
    uint graceDuration = 960 * 21;                    // window for authorative upgrade

    bool nuked;                                       // if true then system has been nuked

    // events (non-ERC)
    event LogDeposit(address indexed _from, uint _value);
    event LogWithdraw(address indexed _to, uint _value);
    event LogChangeCharities(address indexed _charity, bool _isCharity);
    event LogFreeze(address indexed _account, bool frozen);
    event LogAward(uint indexed _time, address _addr, string _state);
    event LogUpgrade(address _addr);

    /// Define ownership, voting parameters, and the Core contract address
    function Ibis(address _core, address [] _owners, uint _ownerThreshold, address nukeMaster) public
	Restricted(_owners, _ownerThreshold, nukeMaster)
	Democratic(VOTE_DURATION)
    {
	graceInit = block.timestamp;
	core = Core(_core);
    }

    ///-------------------------------- User Account Methods --------------------------------///

    /// Return the token balance of an address (ERC20, ERC223)
    function balanceOf(address _owner) public constant returns (uint) {
	return core.balances(_owner);
    }

    /// Transfer value from the sending address to a given recipient (ERC20, ERC223)
    function transfer(address _to, uint _value) public returns (bool) {
	if(core.balances(msg.sender) >= _value) {
	    core.transfer(msg.sender, _to, _value);

	    bytes memory empty;
	    Transfer(msg.sender, _to, _value);
	    Transfer(msg.sender, _to, _value, empty);
	    return true;
	}
    }

    /// Transfer value and invoke handler if sending to a contract (ERC223)
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
    function withdraw(uint _value) public /*suspendable*/ returns (bool) {
	if ((core.charityStatus(msg.sender) || nuked) && _value <= core.balances(msg.sender)) {
	    core.setBalances(msg.sender, core.balances(msg.sender) - _value);
	    totalSupply -= _value;
	    msg.sender.transfer(_value);
	    LogWithdraw(msg.sender, _value);
	    return true;
	}
    }

    /// Convert Ibis coins to Ether on behalf of a charity by an Ibis owner address
    function withdrawFor(address _from, uint _value) public isOwner /*suspendable*/ returns (bool) {
	if ((core.charityStatus(_from) || nuked) && _value <= core.balances(_from)) {
	    core.setBalances(_from, core.balances(_from) - _value);
	    totalSupply -= _value;
	    _from.transfer(_value);
	    LogWithdraw(_from, _value);
	    return true;
	}
    }

    /// Approve a third party address to extract funds (ERC20)
    function approve(address _spender, uint _value) public returns (bool) {
	core.setAllowed(msg.sender, _spender, _value);
	Approval(msg.sender, _spender, _value);
	return true;
    }

    /// Return the amount that an approved third party can withdraw (ERC20)
    function allowance(address _owner, address _spender) public constant returns (uint) {
	return core.allowed(_owner, _spender);
    }

    /// Approve a third party to manange funds and perform a callback (ERC20-ish)
    function approveAndCall(address _spender, uint _value, bytes _extraCore) public returns (bool) {
        core.setAllowed(msg.sender, _spender, _value);
        Approval(msg.sender, _spender, _value);

        if(!_spender.call(bytes4(keccak256("receiveApproval(address,uint,address,bytes)")),
			  msg.sender, _value, this, _extraCore)) {
	    revert();
	}
        return true;
    }

    /// Add a new charity to the whitelist
    function addCharity(address _charity) public isOwner delayed(keccak256(msg.data)) returns (bool) {
	if(!core.charityStatus(_charity)) {
	    core.setCharityStatus(_charity, true);
	    core.setCharityTime(_charity, block.timestamp);
	    LogChangeCharities(_charity, true);
	    return true;
	}
    }

    /// Remove an existing charity from the whitelist
    function removeCharity(address _charity) public isOwner delayed(keccak256(msg.data))
	returns (bool) {
	if(core.charityStatus(_charity)) {
	    core.setCharityStatus(_charity, false);
	    core.setCharityTime(_charity, 0);
	    LogChangeCharities(_charity, false);
	    return true;
	}
    }

    ///---------------------------------- Freeze Methods ------------------------------------///

    /// Suspend accounts by moving the existing balance into a mapping of frozen funds
    function freezeAccounts(address[] _accounts) public isOwner /*suspendable*/ {
	for(uint i = 0; i < _accounts.length; i++) {
	    uint balance = core.balances(_accounts[i]);
	    core.setBalances(_accounts[i], 0);
	    core.setFrozenValue(_accounts[i], balance);
	    core.setFrozenTime(_accounts[i], block.timestamp);
	    LogFreeze(_accounts[i], true);
	}
    }

    /// Reinstantiate frozen funds to the original account
    function unfreezeAccounts(address[] _accounts) public isOwner delayed(keccak256(msg.data))
	/*suspendable*/ {
	for(uint i = 0; i < _accounts.length; i++) {
	    uint frozen = core.frozenValue(_accounts[i]);
	    core.setFrozenValue(_accounts[i], 0);
	    core.setFrozenTime(_accounts[i], 0);
	    core.setBalances(_accounts[i], frozen);
	    LogFreeze(_accounts[i], false);
	}
    }

    /// Liquidate frozen accounts and allow a random charity to claim the funds
    function awardFrozen(address[] _accounts) public isOwner delayed(keccak256(msg.data))
	votable(keccak256(msg.data), MAJORITY) {
	uint frozenAward;

	// loop through frozen accounts to be liquidated
	for(uint i = 0; i < _accounts.length; i++) {

	    // only allow if funds have been frozen for sufficiently long
	    if(block.timestamp < core.frozenTime(_accounts[i]) + frozenMinTime) {
		continue;
	    }

	    // only redistribute up to some max amount of funds per call
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
	awardBlock[block.timestamp] = block.number;
	LogAward(block.timestamp, address(0), "initialized");
    }

    /// Set the award target for a given timestamp to hash of the specified block
    function setTarget(uint _time) public {

	// disallow premature and redudant target setting
	if(awardBlock[_time] == 0 || awardRand[_time] != 0) {
	    return;
	}

	uint targetBlock = awardBlock[_time];

	// usually, the target block will just be the one specified by
	// awardBlock, but since Ethereum only stores the last 256 block hashes
	// we need to make sure we don't loose a source of randomness forever
	if(block.number - targetBlock > 256) {
	    targetBlock = (block.number - 1) - ((block.number - awardBlock[_time]) % 256);
	}

	awardRand[_time] = uint(block.blockhash(targetBlock));
	awardClosest[_time] = MAX_UINT256;
	LogAward(_time, address(0), "set");
    }

    /// Claim that a charity is the closest to the random target for an award
    function claimAward(uint _time, address _charity) public /*suspendable*/ returns (bool) {

	// check that the target was set
	if(awardRand[_time] == 0) {
	    return false;
	}

	// addresses only eligible if they were created before the randomly generated target
	if(core.charityTime(_charity) >= _time) {
	    return false;
	}

	// charity "closeness" defined as Hash(address + rand); smaller is better
	uint challenge = uint(keccak256(uint(_charity) + awardRand[_time]));

	if(challenge < awardClosest[_time]) {
	    awardClosest[_time] = challenge;
	    LogAward(_time, _charity, "claimed");
	    return true;
	}
    }

    /// Move funds into the balance of a winning charity after enough time has passed
    function cashAward(uint _time, address _charity) public /*suspendable*/ returns (bool) {

	// check that the award claim period is over
	if(_time > block.timestamp - awardMinTime) {
	    return false;
	}

	uint claim = uint(keccak256(uint(_charity) + awardRand[_time]));

	// if the claim is valid then clean up and allocate the award
	if(awardClosest[_time] == claim) {
	    uint award = awardValue[_time];
	    delete awardValue[_time];
	    delete awardBlock[_time];
	    delete awardRand[_time];
	    delete awardClosest[_time];
	    core.setBalances(_charity, core.balances(_charity) + award);
	    LogAward(_time, _charity, "awarded");
	    return true;
	}
    }

    /// Set the minimum time for an account to be frozen before distribution
    function setFrozenMinTime(uint _frozenMinTime) public multiowner(keccak256(msg.data))
	delayed(keccak256(msg.data)) {
	frozenMinTime = _frozenMinTime;
    }

    /// Set the window of time that charities can claim an award
    function setAwardMinTime(uint _awardMinTime) public multiowner(keccak256(msg.data))
	delayed(keccak256(msg.data)) {
	awardMinTime = _awardMinTime;
    }

    /// Set the maximum amount of frozen funds that can be posted in a single call
    function setAwardMax(uint _awardMax) public multiowner(keccak256(msg.data))
	delayed(keccak256(msg.data)) {
	awardMax = _awardMax;
    }

    ///---------------------------------- Upgrade Methods -----------------------------------///

    /// Normal path to propose a new controlling contract (multiowner + vote)
    function upgradeStandard(address _addr) public multiowner(keccak256(msg.data)) /*suspendable*/
	votable(keccak256(msg.data), MAJORITY) {
	upgrade(_addr);
    }

    /// Emergency path to upgrade a contract if majority owner keys have been compromised
    function upgradeEmergency(address _addr) public isOwner
	votable(keccak256(msg.data), SUPERMAJORITY) {
	upgrade(_addr);
    }

    /// Emergency path to instantly upgrade if something has gone wrong within the grace period
    function upgradeInitial(address _addr) public isOwner() {
	if(graceInit + graceDuration < block.timestamp) {
	    upgrade(_addr);
	}
    }

    /// Actual upgrade logic
    function upgrade(address _addr) internal {
	if(IbisNew(_addr).init(totalSupply)) {
	    core.upgrade(_addr);
	    LogUpgrade(_addr);
	    selfdestruct(_addr);
	}
    }

    ///---------------------------------- Nuke Methods -----------------------------------///

    /// Supermajority vote to nuke the contract logic and allow free ether withdrawal
    function nuke() isMaster votable(keccak256(msg.data), SUPERMAJORITY) public {
	RestrictedDestruct();
	nuked = true;
    }

    ///------------------------------ Democratic Interface ------------------------------///

    mapping(address => uint) voteBalances;        // number of votes a user has purchased

    /// Obtain votes but temporarily giving up tokens
    function purchaseVotes(address _addr, uint _votes) internal returns (uint) {
	if(_votes <= core.balances(_addr)){
	    voteBalances[_addr] += _votes;
	    core.setBalances(_addr, core.balances(_addr) - _votes);
	    return voteBalances[_addr] + core.frozenValue(_addr);
	}
    }

    /// Retreive tokens once voting is finished
    function returnVotes(address _addr) internal {
	core.setBalances(_addr, core.balances(_addr) + voteBalances[_addr]);
	delete voteBalances[_addr];
    }

}

/// Interface for future transition to the next version of Ibis
contract IbisNew {
    /// This method will be implemented in the future contract version to process legacy data
    function init(uint totalSupply) public returns (bool);
}

/// Interface for ERC223 fallback function
contract ERC223ReceivingContract {
    function tokenFallback(address _from, uint _value, bytes _data) public;
}

/// Concrete instantiation of IbisNew interface for testing purposes only
contract IbisNewConcrete is IbisNew {
    function IbisNewConcrete() public {}
    function init(uint) public returns (bool){return true;}
}
