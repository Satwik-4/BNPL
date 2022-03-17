// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract BNPLAdmin is Ownable, Pausable, ReentrancyGuard{

event InterestUpdated(uint256 revisedInterest); // This event is fired whenever the admins change interest rates. Interest rates are measured in basis points. (1 Basis points = 0.01 percent)
mapping (address => bool) public ERC20IsAccepted; // A mapping from an ERC20 currency address to whether that currency is accepted by this contract
uint256 maxDuration = 26 weeks; // The maximum duration of any BNPL transaction started on this contract, measured in seconds.
uint256 interest = 1600; // The percentage of the interest charged from the buyer

/*constructor(address _network) {

    // Accepted mainnet WETH
    ERC20IsAccepted[_network] = true;

}*/

function Name() external pure returns (string memory){

    return "BNPL Promissory Note";

}

function Symbol() external pure returns (string memory){

    return "BNPL";

}

function updateERC20Accepted(address _contract, bool _set) external onlyOwner {
    // This function can be called by admins to change the acceptance status of an ERC20 currency.
    ERC20IsAccepted[_contract] = _set;

}

function updateMaxDuation(uint256 _newMaxDuration) external onlyOwner {
    // This function can be called by admins to change the maxDuration. 
    require(_newMaxDuration <= uint256(~uint32(0)), "Duration canot exceed space alloted in struct");
    maxDuration = _newMaxDuration;

}

function updateInterest(uint256 _newInterest) external onlyOwner {
    // This function can be called by admins to change the percent of interest rate charged. 
    require(_newInterest <= 10000, "Basis points cannot exceed 10000");
    interest = _newInterest;
    emit InterestUpdated(_newInterest);

}

}