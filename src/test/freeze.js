// TODO: delay problem

var Core = artifacts.require("Core");
var Ibis = artifacts.require("Ibis");

contract("Freeze", function(accounts) {

    var ibis;
    var core;

    var delayDuration;
    var frozenMinTime;
    var awardMinTime;

    owner1 = accounts[0];
    owner2 = accounts[1];
    owner3 = accounts[2];
    nukeMaster = accounts[3];

    user1 = accounts[4];
    user2 = accounts[5];

    charity1 = accounts[6];
    charity2 = accounts[7];

    deposit1 = 2e9;
    transfer1 = 1e9;

    it("should be set up", function() {
	return Ibis.deployed().then(function(instance) {
	    ibis = instance;
	    return Core.deployed()
	}).then(function(instance) {
	    core = instance;
	    return ibis.delayDuration();
	}).then(function(result) {
	    delayDuration = result.toNumber();
	    return ibis.frozenMinTime();
	}).then(function(result) {
	    frozenMinTime = result.toNumber();
	    return ibis.awardMinTime();
	}).then(function(result) {
	    awardMinTime = result.toNumber();
	});
    });

    it("should add charities", function() {
	return ibis.addCharity(charity1, {from: owner1}).then(function() {
	    var wait = {jsonrpc: "2.0", method: "evm_increaseTime", params: [delayDuration], id: 0};
	    web3.currentProvider.send(wait);
	}).then(function() {
	    ibis.addCharity(charity1, {from: owner1});
	}).then(function() {
	    return core.charityStatus(charity1);
	}).then(function(bool) {
	    assert.equal(bool, true, "Charity 1 not registered");
	    return core.charityStatus(charity1);
	});
    });

    it("should allow owners to freeze funds", function() {
	return ibis.deposit({from: user1, value: deposit1}).then(function() {
	    ibis.freezeAccounts([user1], {from: owner1});
	}).then(function() {
	    return ibis.balanceOf(user1);
	}).then(function(balance) {
	    assert.equal(balance.toNumber(), 0, "Balance was not frozen");
	    return core.frozenValue(user1);
	}).then(function(balance) {
	    assert.equal(balance.toNumber(), deposit1, "Frozen funds not stored");
	});
    });

    it("should allow owners to unfreeze funds", function() {
	return ibis.unfreezeAccounts([user1], {from: owner1}).then(function() {
	    return ibis.balanceOf(user1);
	}).then(function(balance) {
	    assert.equal(balance.toNumber(), 0, "Funds should not have been unfrozen yet");
	    var wait = {jsonrpc: "2.0", method: "evm_increaseTime", params: [delayDuration], id: 0};
	    web3.currentProvider.send(wait);
	}).then(function() {
	    ibis.unfreezeAccounts([user1], {from: owner1});
	}).then(function() {
	    return ibis.balanceOf(user1);
	}).then(function(balance) {
	    assert.equal(balance.toNumber(), deposit1, "Funds should have been unfrozen now");
	    return ibis.transfer(user1, transfer1, {from: user1});
	})
    });

    it("should allow frozen funds to be distributed", function() {

	var awardTime;

	return ibis.freezeAccounts([user1, user2], {from: owner1}).then(function() {
	    return ibis.awardExcess([user1, user2], {from: owner1});
	}).then(function(transaction) {
	    awardTime = web3.eth.getBlock(transaction.receipt.blockNumber).timestamp;
	    var wait = {jsonrpc: "2.0", method: "evm_increaseTime", params: [frozenMinTime], id: 0};
	    web3.currentProvider.send(wait);
	}).then(function() {
	    return ibis.awardExcess([user1, user2], {from: owner1});
	}).then(function(transaction) {
	    awardTime = web3.eth.getBlock(transaction.receipt.blockNumber).timestamp;
	    return ibis.awardValue(awardTime);
	});

    });

    // users vote to pass

    // charity 1 claims funds
    // charity 2 claims funds
    // charity 2 attempts to cash out
    // wait a while
    // charity 2 actually cashes out

});
