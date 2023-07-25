// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import {Blue} from "@morpho-blue/Blue.sol";

import {IBlueBulker} from "contracts/interfaces/IBlueBulker.sol";

import {Signature} from "contracts/libraries/Types.sol";
import {Market} from "@morpho-blue/libraries/MarketLib.sol";
import {Math} from "@morpho-utils/math/Math.sol";
import {SafeTransferLib, ERC20} from "@solmate/utils/SafeTransferLib.sol";
import {ERC20 as ERC20Permit2, Permit2Lib} from "@permit2/libraries/Permit2Lib.sol";

/// @title BlueBulker.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Contract allowing to bundle multiple interactions with Blue together.
contract BlueBulker is IBlueBulker {
    using SafeTransferLib for ERC20;
    using Permit2Lib for ERC20Permit2;

    /* IMMUTABLES */

    Blue internal immutable _BLUE;

    /* CONSTRUCTOR */

    constructor(address blue) {
        if (blue == address(0)) revert AddressIsZero();

        _BLUE = Blue(blue);
    }

    /* EXTERNAL */

    /// @notice Executes the given batch of actions, with the given input data.
    ///         Those actions, if not performed in the correct order, with the proper action's configuration
    ///         and with the proper inclusion of skim final calls, could leave funds in the Bulker contract.
    /// @param actions The batch of action to execute, one after the other.
    /// @param data The array of data corresponding to each input action.
    function execute(ActionType[] calldata actions, bytes[] calldata data) external payable {
        uint256 nbActions = actions.length;
        if (nbActions != data.length) {
            revert InconsistentParameters(nbActions, data.length);
        }

        for (uint256 i; i < nbActions; ++i) {
            _performAction(actions[i], data[i]);
        }
    }

    /* INTERNAL */

    /// @dev Performs the given action, given its associated parameters.
    /// @param action The type of action to perform on behalf of the caller.
    /// @param data The data to decode, associated with the action.
    function _performAction(ActionType action, bytes calldata data) internal {
        if (action == ActionType.APPROVE2) {
            _approve2(data);
        } else if (action == ActionType.TRANSFER_FROM2) {
            _transferFrom2(data);
        } else if (action == ActionType.SET_APPROVAL) {
            _setApproval(data);
        } else if (action == ActionType.SUPPLY) {
            _supply(data);
        } else if (action == ActionType.SUPPLY_COLLATERAL) {
            _supplyCollateral(data);
        } else if (action == ActionType.BORROW) {
            _borrow(data);
        } else if (action == ActionType.REPAY) {
            _repay(data);
        } else if (action == ActionType.WITHDRAW) {
            _withdraw(data);
        } else if (action == ActionType.WITHDRAW_COLLATERAL) {
            _withdrawCollateral(data);
        } else if (action == ActionType.SKIM) {
            _skim(data);
        } else {
            revert UnsupportedAction(action);
        }
    }

    /* INTERNAL ACTIONS */

    /// @dev Approves the given `amount` of `asset` from sender to be spent by this contract via Permit2 with the given `deadline` & EIP712 `signature`.
    function _approve2(bytes calldata data) internal {
        (address asset, uint256 amount, uint256 deadline, Signature memory signature) =
            abi.decode(data, (address, uint256, uint256, Signature));
        if (amount == 0) revert AmountIsZero();

        ERC20Permit2(asset).simplePermit2(
            msg.sender, address(this), amount, deadline, signature.v, signature.r, signature.s
        );
    }

    /// @dev Transfers the given `amount` of `asset` from sender to this contract via ERC20 transfer with Permit2 fallback.
    function _transferFrom2(bytes calldata data) internal {
        (address asset, uint256 amount) = abi.decode(data, (address, uint256));
        if (amount == 0) revert AmountIsZero();

        ERC20Permit2(asset).transferFrom2(msg.sender, address(this), amount);
    }

    /// @dev Approves this contract to manage the position of `msg.sender` via EIP712 `signature`.
    function _setApproval(bytes calldata data) internal {
        (bool isAllowed, uint256 nonce, uint256 deadline, Signature memory signature) =
            abi.decode(data, (bool, uint256, uint256, Signature));

        _BLUE.setApproval(msg.sender, address(this), isAllowed, nonce, deadline, signature);
    }

    /// @dev Supplies `amount` of `asset` of `onBehalf` using permit2 in a single tx.
    ///         The supplied amount cannot be used as collateral but is eligible for the peer-to-peer matching.
    function _supply(bytes calldata data) internal {
        (Market memory market, uint256 amount, address onBehalf) = abi.decode(data, (Market, uint256, address));
        if (onBehalf == address(this)) revert AddressIsBulker();

        amount = Math.min(amount, ERC20(address(market.borrowableAsset)).balanceOf(address(this)));

        _approveMaxBlue(address(market.borrowableAsset));

        _BLUE.supply(market, amount, onBehalf);
    }

    /// @dev Supplies `amount` of `asset` collateral to the pool on behalf of `onBehalf`.
    function _supplyCollateral(bytes calldata data) internal {
        (Market memory market, uint256 amount, address onBehalf) = abi.decode(data, (Market, uint256, address));
        if (onBehalf == address(this)) revert AddressIsBulker();

        amount = Math.min(amount, ERC20(address(market.collateralAsset)).balanceOf(address(this)));

        _approveMaxBlue(address(market.collateralAsset));

        _BLUE.supplyCollateral(market, amount, onBehalf);
    }

    /// @dev Borrows `amount` of `asset` on behalf of the sender. Sender must have previously approved the bulker as their manager on Morpho.
    function _borrow(bytes calldata data) internal {
        (Market memory market, uint256 amount, address receiver) = abi.decode(data, (Market, uint256, address));

        _BLUE.borrow(market, amount, msg.sender);
    }

    /// @dev Repays `amount` of `asset` on behalf of `onBehalf`.
    function _repay(bytes calldata data) internal {
        (Market memory market, uint256 amount, address onBehalf) = abi.decode(data, (Market, uint256, address));
        if (onBehalf == address(this)) revert AddressIsBulker();

        amount = Math.min(amount, ERC20(address(market.borrowableAsset)).balanceOf(address(this)));

        _approveMaxBlue(address(market.borrowableAsset));

        _BLUE.repay(market, amount, onBehalf);
    }

    /// @dev Withdraws `amount` of `asset` on behalf of `onBehalf`. Sender must have previously approved the bulker as their manager on Morpho.
    function _withdraw(bytes calldata data) internal {
        (Market memory market, uint256 amount, address receiver) = abi.decode(data, (Market, uint256, address));

        _BLUE.withdraw(market, amount, msg.sender);
    }

    /// @dev Withdraws `amount` of `asset` on behalf of sender. Sender must have previously approved the bulker as their manager on Morpho.
    function _withdrawCollateral(bytes calldata data) internal {
        (Market memory market, uint256 amount, address receiver) = abi.decode(data, (Market, uint256, address));

        _BLUE.withdrawCollateral(market, amount, msg.sender);
    }

    /// @dev Sends any ERC20 in this contract to the receiver.
    function _skim(bytes calldata data) internal {
        (address asset, address receiver) = abi.decode(data, (address, address));
        if (receiver == address(this)) revert AddressIsBulker();
        if (receiver == address(0)) revert AddressIsZero();

        uint256 balance = ERC20(asset).balanceOf(address(this));
        ERC20(asset).safeTransfer(receiver, balance);
    }

    /* INTERNAL HELPERS */

    /// @dev Gives the max approval to the Morpho contract to spend the given `asset` if not already approved.
    function _approveMaxBlue(address asset) internal {
        if (ERC20(asset).allowance(address(this), address(_BLUE)) == 0) {
            ERC20(asset).safeApprove(address(_BLUE), type(uint256).max);
        }
    }
}
