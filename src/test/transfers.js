var Core = artifacts.require("Core");
var Ibis = artifacts.require("Ibis");

contract("Transfers", function(accounts) {

    //todo get system params beforehand

    owner1 = accounts[0];
    owner2 = accounts[1];
    owner3 = accounts[2];
    nukeMaster = accounts[3];

    user1 = accounts[4];
    user2 = accounts[5];

    charity1 = accounts[6];

    var core;
    var ibis;
    var delayDuration;

    var deposit1 = 4e9;
    var deposit2 = 2e9;
    var transfer1 = 1e9;
    var transfer2 = 2e9;
    var withdraw1 = 1e9;

    it("should be set up", function() {
	return Ibis.deployed().then(function(instance) {
	    ibis = instance;
	    return Core.deployed()
	}).then(function(instance) {
	    core = instance;
	    return ibis.delayDuration();
	}).then(function(result) {
	    delayDuration = result.toNumber();
	});
    });

    it("should linked to the Core contract", function() {
	return ibis.core().then(function(address) {
	    assert.equal(address, Core.address, "Core is not linked to Ibis");
	    return core.controller();
	}).then(function(address) {
	    assert.equal(address, Ibis.address, "Ibis is no the controller");
	    return core.approved(Ibis.address);
	}).then(function(bool) {
	    assert.equal(bool, true, "Ibis is not approved");
	});
    });

    it("should accept deposits", function() {

	return ibis.deposit({from: user1, value: deposit1}).then(function () {
	    return ibis.balanceOf(user1);
	}).then(function(balance) {
	    assert.equal(balance.toNumber(), deposit1, "balance of account 1 is incorrect");
	    return ibis.deposit({from: user2, value: deposit2});
	}).then(function() {
	    return ibis.balanceOf(user2);
	}).then(function(balance) {
	    assert.equal(balance.toNumber(), deposit2, "balance of account 2 is incorrect");
	});
    });

    it("should transfer tokens", function() {

	return ibis.transfer(user2, transfer1, {from: user1}).then(function() {
	    return ibis.balanceOf(user1);
	}).then(function(balance) {
	    assert.equal(balance.toNumber(), deposit1 - transfer1, "balance of account 1 is wrong");
	    return ibis.balanceOf(user2);
	}).then(function(balance) {
	    assert.equal(balance.toNumber(), deposit2 + transfer1, "balance of account 2 is wrong");
	    return ibis.transfer(charity1, transfer2, {from: user2});
	}).then(function() {
	    return ibis.balanceOf(charity1);
	}).then(function(balance) {
	    assert.equal(balance.toNumber(), transfer2, "balance of account 2 is wrong");
	});

    });

    it("should allow charities to withdraw", function() {

	var ethOld;
	var ethNew;

	return ibis.addCharity(charity1, {from: owner1}).then(function() {
	    return core.charityStatus(charity1);
	}).then(function(bool) {
	    assert.equal(bool, false, "Should not be a charity yet");
	}).then(function() {
	    var wait = {jsonrpc: "2.0", method: "evm_increaseTime", params: [delayDuration], id: 0};
	    return web3.currentProvider.send(wait);
	}).then(function() {
	    return ibis.addCharity(charity1, {from: owner1});
	}).then(function() {
	    return core.charityStatus(charity1);
	}).then(function(bool) {
	    assert.equal(bool, true, "Should be a charity now");
	    ethOld = web3.eth.getBalance(charity1)
	    return ibis.withdrawOwner(charity1, withdraw1, {from: owner1});
	}).then(function() {
	    return ibis.balanceOf(charity1);
	}).then(function(balance) {
	    assert.equal(balance.toNumber(), transfer2 - withdraw1, "Charity balance did not reduce");
	    ethNew = web3.eth.getBalance(charity1)
	    assert.equal(ethNew.toString(10), ethOld.plus(withdraw1).toString(10), "Did not transfer");
	});
    });
});
