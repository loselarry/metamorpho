// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Blue} from "@morpho-blue/Blue.sol";

import {MarketAllocation} from "contracts/libraries/Types.sol";
import {Permit2Lib, ERC20 as ERC20Permit2} from "@permit2/libraries/Permit2Lib.sol";
import {SafeTransferLib, ERC20} from "@solmate/utils/SafeTransferLib.sol";

import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";

contract InternalSupplyRouter is ERC2771Context {
    using Permit2Lib for ERC20;
    using SafeTransferLib for ERC20;

    Blue internal immutable _BLUE;

    constructor(address blue, address forwarder) ERC2771Context(forwarder) {
        _BLUE = Blue(blue);
    }

    /* INTERNAL */

    function _supplyAll(MarketAllocation[] memory allocations, address onBehalf) internal virtual {
        uint256 nbMarkets = allocations.length;

        for (uint256 i; i < nbMarkets; ++i) {
            MarketAllocation memory allocation = allocations[i];

            _supply(allocation, onBehalf);
        }
    }

    function _withdrawAll(MarketAllocation[] memory allocations, address onBehalf, address receiver) internal virtual {
        uint256 nbMarkets = allocations.length;

        for (uint256 i; i < nbMarkets; ++i) {
            MarketAllocation memory allocation = allocations[i];

            _withdraw(allocation, onBehalf, receiver);
        }
    }

    function _supply(MarketAllocation memory allocation, address onBehalf) internal virtual {
        ERC20(address(allocation.market.borrowableAsset)).transferFrom2(_msgSender(), address(this), allocation.assets);

        _BLUE.supply(allocation.market, allocation.assets, onBehalf);
    }

    function _withdraw(MarketAllocation memory allocation, address onBehalf, address receiver) internal virtual {
        _BLUE.withdraw(allocation.market, allocation.assets, onBehalf);

        ERC20(address(allocation.market.borrowableAsset)).safeTransfer(receiver, allocation.assets);
    }
}
