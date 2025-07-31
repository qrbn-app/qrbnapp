#!/bin/bash

source .env

if [ -z "$1" ]; then
    NETWORK="anvil"
    echo "No network argument provided. Defaulting to 'anvil' (local development network)."
    echo "You can specify a network as: ./deploy.sh <network>"
    echo "Available networks: anvil (default), lisk, lisk_sepolia, sepolia, mainnet"
else
    NETWORK=$1
fi

# Handle Anvil specifically
if [ "$NETWORK" = "anvil" ]; then
    echo "=== ANVIL LOCAL DEPLOYMENT ==="
    echo "Starting Anvil if not already running..."
    
    # Check if Anvil is running
    if ! curl -s http://127.0.0.1:8545 > /dev/null; then
        echo "Anvil not running. Please start it first with:"
        echo "anvil"
        exit 1
    fi
    
    echo "Using Anvil test private key"
fi
    
case $NETWORK in
    "anvil")
        RPC_URL="http://127.0.0.1:8545"
        ;;
    "lisk"|"lisk_sepolia")
        VERIFY_FLAG="--verify --verifier blockscout"
        if [ "$NETWORK" = "lisk_sepolia" ]; then
            RPC_URL="https://rpc.sepolia-api.lisk.com"
            VERIFY_FLAG="$VERIFY_FLAG --verifier-url https://sepolia-blockscout.lisk.com/api"
        else
            RPC_URL="https://rpc.api.lisk.com"
            VERIFY_FLAG="$VERIFY_FLAG --verifier-url https://blockscout.lisk.com/api"
        fi
        ;;
    "sepolia"|"mainnet")
        VERIFY_FLAG="--verify --etherscan-api-key $ETHERSCAN_API_KEY"
        ;;
esac

echo "Deploying to $NETWORK..."

if [ "$NETWORK" = "anvil" ]; then
    DEPLOY_PRIVATE_KEY=$ANVIL_PRIVATE_KEY
else
    DEPLOY_PRIVATE_KEY=$PRIVATE_KEY
fi

forge script DeployQrbn \
--sig "run(address,address,address,address)" \
$INITIAL_FOUNDER_ADDRESS $INITIAL_SYARIAH_COUNCIL_ADDRESS $INITIAL_ORG_REP_ADDRESS $INITIAL_COMMUNITY_REP_ADDRESS \
--rpc-url $RPC_URL \
--private-key $DEPLOY_PRIVATE_KEY \
--broadcast \
$VERIFY_FLAG

echo "Deployment complete!"
