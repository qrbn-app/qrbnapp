// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Governed} from "../dao/Governed.sol";
import {Errors} from "../lib/Errors.sol";

/**
 * @title QrbnTreasury
 * @dev Treasury contract for managing platform fees collected from Qurban platform
 * @notice This contract holds and manages all platform fees with governance control
 */
contract QrbnTreasury is Governed, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct TokenBalance {
        uint256 totalCollected;
        uint256 totalWithdrawn;
        uint256 availableBalance;
    }

    mapping(address => TokenBalance) public tokenBalances;
    address[] public supportedTokens;
    mapping(address => bool) public isSupportedToken;

    // Authorized contracts that can deposit fees (e.g., Qurban contract)
    mapping(address => bool) public authorizedDepositors;

    event FeeDeposited(
        address indexed token,
        address indexed from,
        uint256 amount,
        uint256 newBalance
    );

    event FeeWithdrawn(
        address indexed token,
        address indexed to,
        uint256 amount,
        uint256 remainingBalance
    );

    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event DepositorAuthorized(address indexed depositor);
    event DepositorDeauthorized(address indexed depositor);

    constructor(
        address _timelockAddress,
        address _tempAdminAddress,
        address _usdcToken
    ) Governed(_timelockAddress, _tempAdminAddress) {
        // Add USDC as the first supported token
        _addToken(_usdcToken);
    }

    modifier onlyAuthorizedDepositor() {
        if (!authorizedDepositors[msg.sender]) {
            revert Errors.NotAuthorized("depositor");
        }
        _;
    }

    modifier onlySupportedToken(address _token) {
        if (!isSupportedToken[_token]) {
            revert Errors.TokenNotSupported(_token);
        }
        _;
    }

    /**
     * @notice Add a new token to the treasury
     * @param _token Address of the token to add
     */
    function addToken(address _token) external onlyRole(GOVERNER_ROLE) {
        if (_token == address(0)) {
            revert Errors.AddressZero("token");
        }
        if (isSupportedToken[_token]) {
            revert Errors.TokenAlreadySupported(_token);
        }

        _addToken(_token);
    }

    /**
     * @notice Remove a token from the treasury (only if balance is zero)
     * @param _token Address of the token to remove
     */
    function removeToken(
        address _token
    ) external onlyRole(GOVERNER_ROLE) onlySupportedToken(_token) {
        TokenBalance storage balance = tokenBalances[_token];
        if (balance.availableBalance > 0) {
            revert Errors.TokenBalanceNotZero(_token);
        }

        isSupportedToken[_token] = false;

        // Remove from supportedTokens array
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == _token) {
                supportedTokens[i] = supportedTokens[
                    supportedTokens.length - 1
                ];
                supportedTokens.pop();
                break;
            }
        }

        emit TokenRemoved(_token);
    }

    /**
     * @notice Authorize a contract to deposit fees
     * @param _depositor Address of the depositor contract
     */
    function authorizeDepositor(
        address _depositor
    ) external onlyRole(GOVERNER_ROLE) {
        if (_depositor == address(0)) {
            revert Errors.AddressZero("depositor");
        }
        if (authorizedDepositors[_depositor]) {
            revert Errors.DepositorAlreadyAuthorized(_depositor);
        }

        authorizedDepositors[_depositor] = true;
        emit DepositorAuthorized(_depositor);
    }

    /**
     * @notice Deauthorize a contract from depositing fees
     * @param _depositor Address of the depositor contract
     */
    function deauthorizeDepositor(
        address _depositor
    ) external onlyRole(GOVERNER_ROLE) {
        if (!authorizedDepositors[_depositor]) {
            revert Errors.DepositorNotAuthorized(_depositor);
        }

        authorizedDepositors[_depositor] = false;
        emit DepositorDeauthorized(_depositor);
    }

    /**
     * @notice Deposit platform fees to the treasury
     * @param _token Address of the token being deposited
     * @param _amount Amount to deposit
     */
    function depositFees(
        address _token,
        uint256 _amount
    ) external onlyAuthorizedDepositor onlySupportedToken(_token) nonReentrant {
        if (_amount == 0) {
            revert Errors.InvalidAmount("amount");
        }

        TokenBalance storage balance = tokenBalances[_token];
        IERC20 token = IERC20(_token);

        // Transfer tokens from depositor to treasury
        token.safeTransferFrom(msg.sender, address(this), _amount);

        // Update balances
        balance.totalCollected += _amount;
        balance.availableBalance += _amount;

        emit FeeDeposited(
            _token,
            msg.sender,
            _amount,
            balance.availableBalance
        );
    }

    /**
     * @notice Withdraw fees from treasury to a specified address
     * @param _token Address of the token to withdraw
     * @param _to Address to send the tokens to
     * @param _amount Amount to withdraw
     */
    function withdrawFees(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyRole(GOVERNER_ROLE) onlySupportedToken(_token) nonReentrant {
        if (_to == address(0)) {
            revert Errors.AddressZero("recipient");
        }
        if (_amount == 0) {
            revert Errors.InvalidAmount("amount");
        }

        TokenBalance storage balance = tokenBalances[_token];
        if (balance.availableBalance < _amount) {
            revert Errors.InsufficientBalance(
                _token,
                balance.availableBalance,
                _amount
            );
        }

        // Update balances
        balance.availableBalance -= _amount;
        balance.totalWithdrawn += _amount;

        // Transfer tokens
        IERC20(_token).safeTransfer(_to, _amount);

        emit FeeWithdrawn(_token, _to, _amount, balance.availableBalance);
    }

    /**
     * @notice Get treasury balance for a token
     * @param _token Address of the token
     * @return TokenBalance struct with balance information
     */
    function getTokenBalance(
        address _token
    ) external view returns (TokenBalance memory) {
        return tokenBalances[_token];
    }

    /**
     * @notice Get available balance for a token
     * @param _token Address of the token
     * @return Available balance amount
     */
    function getAvailableBalance(
        address _token
    ) external view returns (uint256) {
        return tokenBalances[_token].availableBalance;
    }

    /**
     * @notice Get all supported tokens
     * @return Array of supported token addresses
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    /**
     * @notice Get total number of supported tokens
     * @return Number of supported tokens
     */
    function getSupportedTokensCount() external view returns (uint256) {
        return supportedTokens.length;
    }

    /**
     * @dev Internal function to add a token
     * @param _token Address of the token to add
     */
    function _addToken(address _token) internal {
        isSupportedToken[_token] = true;
        supportedTokens.push(_token);

        // Initialize token balance struct
        tokenBalances[_token] = TokenBalance({
            totalCollected: 0,
            totalWithdrawn: 0,
            availableBalance: 0
        });

        emit TokenAdded(_token);
    }
}
