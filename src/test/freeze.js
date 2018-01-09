// TODO: delay problem

var Core = artifacts.require("Core");
var Ibis = artifacts.require("Ibis");

contract("Freeze", function(accounts) {

    var ibis;
    var core;

    var delayDuration;
    var voteDuraiton
    var frozenMinTime;
    var awardMinTime;

    var owner1 = accounts[0];
    var owner2 = accounts[1];
    var owner3 = accounts[2];
    var nukeMaster = accounts[3];

    var user1 = accounts[4];
    var user2 = accounts[5];

    var charity1 = accounts[6];
    var charity2 = accounts[7];

    var deposit1 = 2e9;
    var transfer1 = 1e9;

    var awardIssue;
    var awardTime;


    it("should be set up", function() {
	return Ibis.deployed().then(function(instance) {
	    ibis = instance;
	    return Core.deployed()
	}).then(function(instance) {
	    core = instance;
	    return ibis.delayDuration();
	}).then(function(result) {
	    delayDuration = result.toNumber();
	    return ibis.voteDuration();
	}).then(function(result) {
	    voteDuration = result.toNumber();
	    return ibis.frozenMinTime();
	}).then(function(result) {
	    frozenMinTime = result.toNumber();
	    return ibis.awardMinTime();
	}).then(function(result) {
	    awardMinTime = result.toNumber();
	});
    });

    it("should add charities", function() {

	var operation1;
	var operation2;

	return ibis.addCharity(charity1, {from: owner1}).then(function(transaction) {
	    return ibis.addCharity(charity2, {from: owner1});
	}).then(function() {
	    var wait = {jsonrpc: "2.0", method: "evm_increaseTime", params: [delayDuration], id: 0};
	    return web3.currentProvider.send(wait);
	}).then(function(){
	    return ibis.addCharity(charity1, {from: owner1});
	}).then(function() {
	    return ibis.addCharity(charity2, {from: owner1});
	}).then(function() {
	    return core.charityStatus(charity1);
	}).then(function(bool) {
	    assert.equal(bool, true, "Charity 1 not registered");
	    return core.charityStatus(charity2);
	}).then(function(bool) {
	    assert.equal(bool, true, "Charity 2 not registered");
	});
    });

    it("should allow owners to freeze funds", function() {
	return ibis.deposit({from: user1, value: deposit1}).then(function() {
	    return ibis.freezeAccounts([user1], {from: owner1});
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
	    return web3.currentProvider.send(wait);
	}).then(function() {
	    return ibis.unfreezeAccounts([user1], {from: owner1});
	}).then(function() {
	    return ibis.balanceOf(user1);
	}).then(function(balance) {
	    assert.equal(balance.toNumber(), deposit1, "Funds should have been unfrozen now");
	    return ibis.transfer(user2, transfer1, {from: user1});
	})
    });

    it("should allow frozen funds to be distributed", function() {

	return ibis.freezeAccounts([user1, user2], {from: owner1}).then(function() {
	    var wait = {jsonrpc: "2.0", method: "evm_increaseTime", params: [frozenMinTime], id: 0};
	    return web3.currentProvider.send(wait);
 	}).then(function(transaction) {
	    return ibis.awardExcess([user1, user2], {from: owner1});
	}).then(function() {
	    var wait = {jsonrpc: "2.0", method: "evm_increaseTime", params: [delayDuration], id: 0};
	    return web3.currentProvider.send(wait);
 	}).then(function() {
	    return ibis.awardExcess([user1, user2], {from: owner1});
	}).then(function(transaction) {
	    var data = web3.eth.getTransaction(transaction.tx).input
	    awardIssue = web3.sha3(data, {encoding: "hex"});
	    return ibis.register(0, {from: user1});
	}).then(function() {
	    return ibis.vote(awardIssue, true, {from: user1});
	}).then(function() {
	    var wait = {jsonrpc: "2.0", method: "evm_increaseTime", params: [voteDuration], id: 0};
	    return web3.currentProvider.send(wait);
	}).then(function() {
	    return ibis.awardExcess([user1, user2], {from: owner1});
	}).then(function(transaction) {
	    awardTime = web3.eth.getBlock(transaction.receipt.blockNumber).timestamp;
	    return ibis.awardValue(awardTime);
	}).then(function(result) {
	    assert.equal(result.toNumber(), deposit1, "Award value incorrect");
	});
    });

    it("should allow charities to claim awards", function() {
	console.log(charity1);

	var hash = web3.sha3(charity1, {encoding: "hex"});
	console.log(hash);

	var deci1 = web3.toDecimal(hash.slice(0, 16));
	var deci2 = web3.toDecimal(hash.slice(0, 16));

	console.log(deci);

	var hash2 = web3.fromDecimal(deci);
	console.log(hash2);
    });

    // charity 1 claims funds
    // charity 2 claims funds
    // charity 2 attempts to cash out
    // wait a while
    // charity 2 actually cashes out

});
