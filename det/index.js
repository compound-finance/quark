var http = require("http"),
  httpProxy = require("http-proxy"),
  express = require("express"),
  bodyParser = require("body-parser"),
  { ethers, getNumber, Transaction } = require("ethers");

let infuraKey = process.argv[2];
if (!infuraKey) {
  throw new Error(`Infura Key Missing, use \`npm run start {infuraKey}\``);
}

let proxy = httpProxy.createProxyServer({});

proxy.on("proxyReq", function (proxyReq, req, res, options) {
  proxyReq.path = `/v3/${infuraKey}`;
  if (req.body) {
    let bodyData = JSON.stringify(req.body);
    proxyReq.setHeader("Content-Type", "application/json");
    proxyReq.setHeader("Content-Length", Buffer.byteLength(bodyData));
    proxyReq.write(bodyData);
  }
});

function parseJsonRpc(msg) {
  if (msg.jsonrpc !== "2.0") {
    throw new Error("Invalid JSON-RPC request");
  }

  return {
    id: msg.id,
    method: msg.method,
    params: msg.params,
  };
}

const proxyApp = express();
proxyApp.use(bodyParser.json());
proxyApp.use(bodyParser.urlencoded({ extended: true }));
proxyApp.use(function (req, res) {
  let { id, method, params } = parseJsonRpc(req.body);
  console.log(`RPC Request [${id}]  ${method}`);

  if (method === "eth_sendTransaction") {
    let txParams = params[0];
    delete txParams.from;
    txParams.type = getNumber(txParams.type);
    txParams.gasLimit = getNumber(txParams.gas);
    txParams.maxPriorityFeePerGas = getNumber(txParams.maxPriorityFeePerGas);
    txParams.maxFeePerGas = getNumber(txParams.maxFeePerGas);
    txParams.chainId = 5;
    txParams.signature = {
      v: 27,
      r: "0x2222222222222222222222222222222222222222222222222222222222222222",
      s: "0x2222222222222222222222222222222222222222222222222222222222222222  ",
    };
    console.log(`Rebuilding eth_sendTransaction with tx params`, txParams);
    let tx = Transaction.from(txParams);
    console.log(
      `Submitting eth_sendRawTx with txHash=${tx.hash}, sender=${tx.from}`,
    );

    req.body = {
      jsonrpc: "2.0",
      id,
      method: "eth_sendRawTransaction",
      params: [tx.serialized],
    };
  }

  proxy.web(req, res, {
    changeOrigin: true,
    target: "https://goerli.infura.io",
  });
});

http.createServer(proxyApp).listen(8545, "0.0.0.0", () => {
  console.log("Det Proxy running on http://localhost:8545");
});
