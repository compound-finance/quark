## Det

First install:

```sh
npm run install
```

Start the proxy server with:

```sh
cd det && npm run start {infuraKey}
```

And deploy a contract with:

```sh
forge create --rpc-url http://localhost:8545 --unlocked --from 0x0000000000000000000000000000000000000000 --gas-limit 100000 --gas-price 10000000000 --priority-gas-price 0 --verify CodeJar
```
