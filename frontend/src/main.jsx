import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App.jsx";
import "./index.css";
import { WagmiConfig, configureChains, createConfig, mainnet } from "wagmi";
import { ConnectKitProvider, getDefaultConfig } from "connectkit";
import { jsonRpcProvider } from "wagmi/providers/jsonRpc";

const { chains } = configureChains(
  [mainnet],
  [
    jsonRpcProvider({
      rpc: () => ({
        http: "http://localhost:8545",
      }),
    }),
  ]
);

const config = createConfig(
  getDefaultConfig({
    // Required API Keys
    // infuraId: "https://mainnet.infura.io/v3/ea7694b48de6476b8370bf72998db9ab", // or infuraId
    walletConnectProjectId: "6f631db1124231fc259a2bb540f80932",

    chains,
    // Required
    appName: "Compound Quark Leveragoor",

    // Optional
    appDescription: "Compound Quark Leveragoor",
    appUrl: "https://compound.finance", // your app's url
    // appIcon: "https://family.co/logo.png", // your app's icon, no bigger than 1024x1024px (max. 1MB)
  })
);

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <WagmiConfig config={config}>
      <ConnectKitProvider>
        <App />
      </ConnectKitProvider>
    </WagmiConfig>
  </React.StrictMode>
);
