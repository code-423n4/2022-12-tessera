.PHONY: all test clean

ifndef m
override m = test
endif

all: prettier test
build :; forge build
test :; forge test -vvv --match-test $(m) 
report :; forge test --gas-report -vvv --optimize
deps :; git submodule update --init --recursive
install :; npm ci
prettier :; npm run prettier
test-nofork :; forge test -vvv --no-match-contract Seaport
test-fork :; forge test -vvv --match-contract Seaport
