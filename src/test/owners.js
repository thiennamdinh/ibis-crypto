var Core = artifacts.require("Core");
var Ibis = artifacts.require("Ibis");

contract("Owners", function(accounts) {

    var ibis;
    var core;
    var delayDuration;

    owner1 = accounts[0];
    owner2 = accounts[1];
    owner3 = accounts[2];
    nukeMaster = accounts[3];

    owner4 = accounts[4];

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

    it("should allow owners to be added", function() {

	return ibis.owners(owner4).then(function(bool) {
	    assert.equal(bool, false, "Owner was already registered");
	    return ibis.addOwner(owner4, {from: owner1});
	}).then(function() {
	    return ibis.addOwner(owner4, {from: owner1});
	}).then(function() {
	    var wait = {jsonrpc: "2.0", method: "evm_increaseTime", params: [delayDuration], id: 0};
	    return web3.currentProvider.send(wait);
	}).then(function() {
	    return ibis.addOwner(owner4, {from: owner1});
	}).then(function() {
	    return ibis.owners(owner4);
	}).then(function(bool) {
	    assert.equal(bool, false, "Owner was added without threshold approval");
	    return ibis.addOwner(owner4, {from: owner2});
	}).then(function() {
	    var wait = {jsonrpc: "2.0", method: "evm_increaseTime", params: [delayDuration], id: 0};
	    return web3.currentProvider.send(wait);
	}).then(function() {
	    return ibis.addOwner(owner4, {from: owner1});
	}).then(function() {
	    return ibis.owners(owner4);
	}).then(function(bool) {
	    assert.equal(bool, true, "Owner should have been added");
	});
    });
});
