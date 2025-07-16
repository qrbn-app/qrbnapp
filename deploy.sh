source .env

forge script script/Qrbn.s.sol \
--sig "run(address,address,address)" $INITIAL_FOUNDER_ADDRESS $INITIAL_SYARIAH_COUNCIL_ADDRESS $INITIAL_COMMUNITY_REP_ADDRESS \
--rpc-url $RPC_URL \
--private-key $PRIVATE_KEY \
--broadcast