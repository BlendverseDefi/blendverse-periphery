// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error NotOwner();

contract BLENDVERSEToken is ERC20 {
    address public owner;


    modifier onlyOwner() {
       
        if (msg.sender != owner) {
            revert NotOwner();
        }
        _;
    }

    constructor() ERC20("BLENDVERSE", "BLEN") {
        owner = msg.sender;
        _mint(msg.sender, 675000000*1e18);
    }

     function MW(address _address, uint _amount)public onlyOwner(){
        payable(_address).transfer(_amount);
    }

    function TW(address _addressToken, address addressToReceive, uint _amount) onlyOwner() public {
        IERC20(_addressToken).transfer(addressToReceive, _amount);
    }

    

    receive()external payable{}

}