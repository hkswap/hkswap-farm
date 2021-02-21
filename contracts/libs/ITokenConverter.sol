// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface ITokenConverter {
    /**
     * @dev Converts the srcLpToken Amount to destLpToken and transfers converted destLpToken amount to msg.sender.
     * Remains should be repaid to originalSender.
     * Returns the transferred amount of destToken
     *
     * should Emits an {Convert} event.
     */

    function convertAndRePaid( address _srcLpToken, uint256 _srcTokenAmount, address _destToken, address originalSender) external returns (uint256);

    /**
    * @dev Emitted when a conversion is done.
    *
    */
    event Convert(address indexed originalSender, address srcToken, uint256 srcAmount, address destToken, uint256 destAmount, bool hasRemain);
}
