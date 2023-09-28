import "./App.css";
import { ConnectKitButton } from "connectkit";

function App() {
  const onClickMaxLeverage = () => {};

  return (
    <>
      <div className="flex justify-end mb-8">
        <ConnectKitButton />
      </div>
      <h1 className="text-3xl font-bold mb-8">Compound Quark Leveragoor</h1>

      <button onClick={onClickMaxLeverage}>Full Degen Mode</button>
    </>
  );
}

export default App;
