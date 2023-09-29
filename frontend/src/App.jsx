import { useSignTypedData, useContractWrite, useSignMessage } from "wagmi";
import "./App.css";
import { ConnectKitButton } from "connectkit";
import {
  abi as leverFlashLoanABI,
  deployedBytecode as leverFlashLoanBytecode,
} from "../../out/LeverFlashLoan.sol/LeverFlashLoan.json";
import { abi as QuarkWalletABI } from "../../out/QuarkWallet.sol/QuarkWallet.json";
import {
  encodeFunctionData,
  parseEther,
  hexToNumber,
  toHex,
  toBytes,
} from "viem";
import { secp256k1 } from "@noble/curves/secp256k1";

function App() {
  const deployedQuarkWallet = "0xda9A4789644bD84A0Ba75128272Af34DB8887594";
  const cometUsdcEth = "0xc3d688B66703497DAA19211EEdff47f25384cdc3";
  const wethAssetIndex = 2;
  const collateralAmount = parseEther("1");

  const domain = {
    name: "Quark Wallet",
    version: "1",
    chainId: 1,
    verifyingContract: deployedQuarkWallet,
  };

  const types = {
    QuarkOperation: [
      { name: "scriptSource", type: "bytes" },
      { name: "scriptCalldata", type: "bytes" },
      { name: "nonce", type: "uint256" },
      { name: "expiry", type: "uint256" },
      { name: "admitCallback", type: "bool" },
    ],
  };

  const scriptCalldata = encodeFunctionData({
    abi: leverFlashLoanABI,
    functionName: "run",
    args: [cometUsdcEth, wethAssetIndex, collateralAmount],
  });

  const message = {
    scriptSource: leverFlashLoanBytecode.object,
    scriptCalldata: scriptCalldata,
    nonce: 0,
    expiry: 10695928823,
    admitCallback: true,
  };

  const { data: signTransactionData, signTypedData } = useSignTypedData({
    domain,
    types,
    primaryType: "QuarkOperation",
    message,
  });

  let r, s, v;

  if (signTransactionData !== undefined) {
    r = secp256k1.Signature.fromCompact(signTransactionData.slice(2, 130)).r;
    r = toHex(r);
    s = secp256k1.Signature.fromCompact(signTransactionData.slice(2, 130)).s;
    s = toHex(s);
    v = `0x${signTransactionData.slice(130)}`;
  }

  const { write } = useContractWrite({
    address: deployedQuarkWallet,
    abi: QuarkWalletABI,
    functionName: "executeQuarkOperation",
    args: [message, v, r, s],
  });

  const onClickSign = () => {
    signTypedData();
  };

  const onClickSubmit = () => {
    write();
  };

  // res.signTypedData({
  //   types: {
  //     EIP712Domain: domain,
  //   },
  //   domain,
  //   primaryType: "QuarkOperation",
  //   message: {
  //     name: "Quark Wallet",
  //     version: "1",
  //     chainId: 1,
  //     verifyingContract: deployedQuarkWallet,
  //   },
  // });

  // console.log(res);

  const getButton = () => {
    if (signTransactionData === undefined) {
      return <button onClick={onClickSign}>Full Degen Mode</button>;
    } else {
      return <button onClick={onClickSubmit}>Submit Transaction</button>;
    }
  };

  return (
    <>
      <div className="flex justify-end mb-8">
        <ConnectKitButton />
      </div>
      <h1 className="text-3xl font-bold mb-8">Compound Quark Leveragoor</h1>
      {getButton()}
    </>
  );
}

export default App;
