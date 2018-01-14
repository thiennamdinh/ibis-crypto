/**
 * Define functions and modifiers needed to implement a democratic voting
 * system. Voting stake can be obtained by "registering". A user's voting power
 * is determined by the inheriting contract with the intention. Once registered,
 * users can declare support or dissent for any active issue, identifiable by
 * its message data.
 */

pragma solidity ^0.4.13;

contract Democratic {

    // possible  voting states
    enum Ballot {UNDECIDED, SUPPORTING, DISSENTING}

    // state of a single open operation that can be voted on
    struct Issue {
	uint initTime;              // time at which an issue was first opened
	uint threshold;             // percentage support (0-100) required to pass the vote

	uint supportingTotal;       // total votes in favor of the operation
	uint dissentingTotal;       // total against the operation

	mapping(address => Ballot) ballots;    // track individual votes
    }

    uint public voteDuration;       // window of time available to vote on an issue

    // variables to track voting issues
    uint activeIssues;                                  // number of issues currently open for vote
    mapping(bytes32 => Issue) public issues;            // map of active issues to be voted on
    mapping(address => uint) public numParticipating;   // number of issues participated by address
    mapping(address => uint) public votingStake;        // balance that a user has spent on voting power

    // democratic events
    event LogRegister(address indexed _addr, bool registered);
    event LogVote(address indexed _addr, Ballot vote);
    event LogIssue(bytes32 indexed _operation, string status);

    /// Function call must be approved by a majority of token stakeholders
    modifier votable(bytes32 _operation, uint percent) {
	if(!checkVotes(_operation, percent)) {
	    assembly{stop}
	}
	_;
	delete issues[_operation];
    }

    /// Set constructor parameters
    function Democratic(uint _voteDuration) public {
	voteDuration = _voteDuration;
    }

    /// Register to vote. Cannot call this method more than once before unregistering
    function register(uint _votes) public {
	// cannot register if already registered
	if(votingStake[msg.sender] == 0) {
	    votingStake[msg.sender] = purchaseVotes(msg.sender, _votes);
	    LogRegister(msg.sender, true);
	}
    }

    /// Unregister voting rights if not participating in any issues
    function unregister() public {
	if(votingStake[msg.sender] != 0 && numParticipating[msg.sender] == 0) {
	    delete votingStake[msg.sender];
	    returnVotes(msg.sender);
	    LogRegister(msg.sender, false);
	}
    }

    /// Allow anybody to unregister a voter if there are no active issues at all
    function unregisterFor(address _addr) public {
	if(votingStake[_addr] != 0 && activeIssues == 0) {
	    delete votingStake[_addr];
	    returnVotes(_addr);
	    LogRegister(_addr, false);
	}
    }

    /// Declare support or dissent of a votable issue
    function vote(bytes32 _operation, bool _supporting) public {

	// already voted on this issue
	if(issues[_operation].ballots[msg.sender] != Ballot.UNDECIDED) {
	    return;
	}

	// reference the issue created in "publicVote"
	if(_supporting) {
	    issues[_operation].ballots[msg.sender] = Ballot.SUPPORTING;
	    issues[_operation].supportingTotal += votingStake[msg.sender];
	    LogVote(msg.sender, Ballot.SUPPORTING);
	}
	else {
	    issues[_operation].ballots[msg.sender] = Ballot.DISSENTING;
	    issues[_operation].dissentingTotal += votingStake[msg.sender];
	    LogVote(msg.sender, Ballot.DISSENTING);
	}

	numParticipating[msg.sender]++;
    }

    /// Withdraw vote from a given issue
    function unvote(bytes32 _operation) public {

	// check that user hasn't voted on this issue already
	if(issues[_operation].ballots[msg.sender] == Ballot.UNDECIDED) {
	    return;
	}

	// update the voting counts
	if(issues[_operation].ballots[msg.sender] == Ballot.SUPPORTING) {
	    issues[_operation].supportingTotal -= votingStake[msg.sender];
	}
	else if(issues[_operation].ballots[msg.sender] == Ballot.DISSENTING) {
	    issues[_operation].dissentingTotal -= votingStake[msg.sender];
	}

	// update user state
	numParticipating[msg.sender]--;
	issues[_operation].ballots[msg.sender] = Ballot.UNDECIDED;
	LogVote(msg.sender, Ballot.UNDECIDED);
    }

    // Allow anybody to clear the space occupied by a closed issue
    function clearVote(bytes32 _operation, address _addr) public {
	if(block.timestamp < issues[_operation].initTime + voteDuration) {
	    if(issues[_operation].ballots[_addr] != Ballot.UNDECIDED) {
		numParticipating[_addr]--;
	    }

	    delete issues[_operation].ballots[_addr];
	    LogVote(_addr, Ballot.UNDECIDED);
	}
    }

    /// Updating voting state or tally final count if the deadline has passed
    function checkVotes(bytes32 _operation, uint _percent)
	private returns (bool) {

	// if this is the first call then create a new issue and set the initial block time
	if(issues[_operation].initTime == 0) {

	    issues[_operation].initTime = block.timestamp;
	    issues[_operation].threshold = _percent;
	    activeIssues++;

	    LogIssue(_operation, "initialized");
	    return false;
	}

	// if the voting period has ended then tally the votes and return the result
	if (block.timestamp >= issues[_operation].initTime + voteDuration) {
	    activeIssues--;
	    issues[_operation].threshold = 5;

 	    uint total = issues[_operation].supportingTotal + issues[_operation].dissentingTotal;

	    LogIssue(_operation, "closed");
	    return issues[_operation].supportingTotal * 100 > total * issues[_operation].threshold;
	}
    }

    ///---------------------------------- Abstract Methods ----------------------------------///

    /// Update state in child contract to prevent sybil voting
    function purchaseVotes(address _addr, uint _votes) internal returns (uint);

    /// Restore pre-voting state to child contract
    function returnVotes(address _addr) internal;
}
