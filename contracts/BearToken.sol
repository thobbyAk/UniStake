pragma solidity ^0.8.11; // Designate version of solidity

import "@openzeppelin/contracts/token/ERC20/ERC20.sol"; // ERC20 template

contract BearToken is
    ERC20 // Create contract using ERC20 interface
{
    constructor() ERC20("Bare Token", "BTK") {
        // Token Name and Ticker
        _mint(msg.sender, 100000); // Mint 10000 tokens at beginning
    }

    function mint(address to, uint256 amount) external {
        uint256 dayOfWeek = ((block.timestamp / 86400) + 4) % 7; // 0 = Sunday, 1 = Monday, etc

        require(dayOfWeek != 5); // Require that today is not friday
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) external {
        uint256 dayOfWeek = ((block.timestamp / 86400) + 4) % 7; // 0 = Sunday, 1 = Monday, etc

        require(dayOfWeek != 5); // Require that today is not friday
        _burn(to, amount);
    }
}
