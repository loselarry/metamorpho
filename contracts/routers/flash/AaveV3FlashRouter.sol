// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {IAaveFlashLender} from "./interfaces/IAaveFlashLender.sol";

import {Errors} from "./libraries/Errors.sol";

import {AaveFlashRouter} from "./AaveFlashRouter.sol";

contract AaveV3FlashRouter is AaveFlashRouter {
    /* IMMUTABLES */

    IAaveFlashLender internal immutable _AAVE_V3;

    /* CONSTRUCTOR */

    constructor(address aaveV3) {
        require(aaveV3 != address(0), Errors.ZERO_ADDRESS);

        _AAVE_V3 = IAaveFlashLender(aaveV3);
    }

    /* ACTIONS */

    /// @dev Triggers a flash loan on AaveV3.
    function aaveV3FlashLoan(address[] calldata assets, uint256[] calldata amounts, bytes calldata data) external {
        _aaveFlashLoan(_AAVE_V3, assets, amounts, data);
    }
}