module.exports = {
    // See <http://truffleframework.com/docs/advanced/configuration>
    // to customize your Truffle configuration!

    networks: {
	development: {
	    host: "127.0.0.1",
	    port: 8545,
	    network_id: "*", // match any network
	},

	test: {
	    host: "127.0.0.1",
	    port: 8545,
	    network_id: "*",
	}
    },

    solc: {
	optimizer: {
	    enabled: true,
	    runs: 300
	}
    }
};
