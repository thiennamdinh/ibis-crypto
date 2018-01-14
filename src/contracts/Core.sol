/**
 * Track the core values of the charity currency state. This contract will be
 * valid for the rest of time. At any given point, there will be one master
 * controller contract for the currency. This controller will in turn delegate
 * the ability to modify core state. In the event of an upgrade to the
 * controller, approved contracts should be removed and a new address supplied
 * to the Core contract.
 *
 * The Core contract tracks precisely the following state:
 *     - Token balances
 *     - ERC20 allowed spenders
 *     - Flags declaring designated charity addresses
 *     - Time at which a charity was last added
 *     - Temporarily frozen user funds
 *     - Time at which funds were frozen
 */

pragma solidity ^0.4.13;

contract Core {

    address public controller;
    mapping(address => bool) public approved;

    mapping(address => uint) public balances;
    mapping(address => mapping (address => uint)) public allowed;
    mapping(address => bool) public charityStatus;
    mapping(address => uint) public charityTime;
    mapping(address => uint) public frozenValue;
    mapping(address => uint) public frozenTime;

    modifier isController() {
	require(msg.sender == controller);
	_;
    }

    modifier isApproved() {
	require(approved[msg.sender]);
	_;
    }

    function Core() public {
	controller = msg.sender;
    }

    function upgrade(address _addr) public {
	controller = _addr;
    }

    function addApproved(address _addr) public isController {
	approved[_addr] = true;
    }

    function removeApproved(address _addr) public isController {
	approved[_addr] = false;
    }

    function setBalances(address _addr, uint _value) public isApproved {
	balances[_addr] = _value;
    }

    function setCharityStatus(address _addr, bool _status) public isApproved {
	charityStatus[_addr] = _status;
    }

    function setCharityTime(address _addr, uint _time) public isApproved {
	charityTime[_addr] = _time;
    }

    function setAllowed(address _addr, address _allowed, uint _value) public isApproved {
	allowed[_addr][_allowed] = _value;
    }

    function setFrozenValue(address _addr, uint _value) public isApproved {
	frozenValue[_addr] = _value;
    }

    function setFrozenTime(address _addr, uint _time) public isApproved {
	frozenTime[_addr] = _time;
    }

    function transfer(address _to, address _from,  uint _value) public isApproved {
	balances[_to] -= _value;
	balances[_from] += _value;
    }
}
