const HKSToken = artifacts.require("HKSToken");
const MasterChef = artifacts.require("MasterChef");

module.exports = function (deployer, accounts) {
	deployer.deploy(HKSToken)
	.then(function(){
        return deployer.deploy(MasterChef, HKSToken.address,'','', 0, 0)

    })
};
