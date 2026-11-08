import { useState } from 'react'
import Header from './components/Header'
import CreateTokenForm from './components/CreateTokenForm'
import TokenList from './components/TokenList'
import TradePanel from './components/TradePanel'
import { ToastProvider } from './components/Toast'
import { WalletProvider } from './lib/wallet'
import type { TokenListItem } from './lib/api'
import { CORE_ADDRESS, FACTORY_ADDRESS } from './config'
import { shortAddr } from './utils/format'

export default function App() {
  const [refreshKey, setRefreshKey] = useState(0)
  const [selected, setSelected] = useState<TokenListItem | null>(null)

  const bump = () => setRefreshKey((k) => k + 1)

  return (
    <ToastProvider>
      <WalletProvider>
        <div className="page">
          <Header />
          <div className="stats-bar">
            <div className="stat-item">
              <span className="k">定价模型</span>
              <span className="v">恒定乘积联合曲线 x·y=k</span>
            </div>
            <div className="stat-item">
              <span className="k">Core 合约</span>
              <span className="v mono">{shortAddr(CORE_ADDRESS, 10, 6)}</span>
            </div>
            <div className="stat-item">
              <span className="k">Factory</span>
              <span className="v mono">{shortAddr(FACTORY_ADDRESS, 10, 6)}</span>
            </div>
            <div className="stat-item">
              <span className="k">技术栈</span>
              <span className="v">Solidity · Go · React+TS · ethers v6</span>
            </div>
          </div>
          <main className="layout">
            <CreateTokenForm onCreated={bump} />
            <TokenList
              refreshKey={refreshKey}
              selected={selected?.tokenAddr}
              onSelect={setSelected}
            />
          </main>
          <footer className="footer">
            anvil(8545) · Go API(38080) · Indexer 轮询同步 · Vite + React + TS +
            ethers v6 + lightweight-charts
          </footer>
          {selected && (
            <TradePanel
              token={selected}
              onClose={() => setSelected(null)}
              onTraded={bump}
            />
          )}
        </div>
      </WalletProvider>
    </ToastProvider>
  )
}
