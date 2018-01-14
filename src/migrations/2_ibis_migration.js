var Core = artifacts.require("Core");
var Ibis = artifacts.require("Ibis");
var IbisUpgrade = artifacts.require("IbisNewConcrete");

module.exports = function(deployer, network, accounts) {

    var core;
    price = 7e9;

    if(network == "development") {
	owner1 = accounts[0];
	owner2 = accounts[1];
	owner3 = accounts[2];
	master = accounts[3];
    } else {
	owner1 = '0xa35daa4e1c50539876e9fee3e93524d2bca9c6d8'
	owner2 = '0x54fa09683cd28349d4a8bc75ab6d5a0c7e0f123e'
	owner3 = '0x9a97dd41b0824552cbc52f73de9d35f3d4904a78'
	master = '0x3aa344428c8c67123d99a81b8fa3793121153f6b'
    }

    deployer.deploy(Core, {from: owner1, gasPrice: price}).then(function(){
	return deployer.deploy(Ibis, Core.address, [owner1, owner2, owner3], 2,
			       master, {from: owner1, gas: 6000000, gasPrice: price});
    }).then(function() {
	return Core.deployed();
    }).then(function(instance) {
	core = instance;
	core.addApproved(Ibis.address, {from: owner1, gasPrice: price})
    }).then(function() {
	core.upgrade(Ibis.address, {from: owner1, gasPrice: price});
    });

    if(network == "development"){
	deployer.deploy(IbisUpgrade, {from: owner1, gasPrice: price});
    }

};
