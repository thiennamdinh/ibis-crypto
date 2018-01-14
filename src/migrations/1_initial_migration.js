var Migrations = artifacts.require("Migrations");

module.exports = function(deployer, network, accounts) {

    if(network == "development") {
	owner1 = accounts[0];
    } else {
	owner1 = '0xa35daa4e1c50539876e9fee3e93524d2bca9c6d8'
    }

    price = 7e9;

    deployer.deploy(Migrations, {from: owner1, gasPrice: price});
};
