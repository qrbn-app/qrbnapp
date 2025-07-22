// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

library Errors {
    error AddressZero(string entity);
    error AlreadyRegistered(string entity);
    error NotVerified(string entity);
    error NotRegistered(string entity);
    error EmptyString(string field);
    error AlreadyVerified(string entity);
    error AlreadyUnverified(string entity);
    error InvalidAmount(string field);
    error InvalidDate(string field);
    error NotAvailable(string entity);
    error AlreadyAvailable(string entity);
    error AlreadyPending(string entity);
    error AlreadyPurchased(string entity);
    error Forbidden(string field);
    error NotAuthorized(string entity);
    error TokenNotSupported(address token);
    error TokenAlreadySupported(address token);
    error TokenBalanceNotZero(address token);
    error DepositorAlreadyAuthorized(address depositor);
    error DepositorNotAuthorized(address depositor);
    error InsufficientBalance(
        address token,
        uint256 available,
        uint256 requested
    );
}
