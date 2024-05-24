// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

interface IZUSD {
    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function mint(address _recipient, uint256 _mintAmount) external;

    function burn(address _account, uint256 burnAmount) external;
}
