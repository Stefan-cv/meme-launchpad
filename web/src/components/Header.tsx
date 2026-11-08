import { useEffect, useState } from 'react'
import { JsonRpcProvider, formatEther } from 'ethers'
import { RPC_URL } from '../config'
import { useWallet } from '../lib/wallet'
import { copyText, shortAddr } from '../utils/format'
import { useToast } from './Toast'

const provider = new JsonRpcProvider(RPC_URL)

export default function Header() {
  const { kind, address, jwt, busy, error, connect, disconnect } = useWallet()
  const { push } = useToast()
  const [ethBalance, setEthBalance] = useState<string | null>(null)

  useEffect(() => {
    if (!address) {
      setEthBalance(null)
      return
    }
    let alive = true
    const load = () =>
      provider
        .getBalance(address)
        .then((b) => alive && setEthBalance(parseFloat(formatEther(b)).toFixed(3)))
        .catch(() => undefined)
    load()
    const timer = setInterval(load, 10_000)
    return () => {
      alive = false
      clearInterval(timer)
    }
  }, [address])

  async function onCopy() {
    if (!address) return
    if (await copyText(address)) push('info', '地址已复制到剪贴板')
  }

  return (
    <header className="header">
      <div className="brand">
        <span className="logo">🚀</span>
        <div>
          <h1>MEME Launchpad</h1>
          <span className="sub">Bonding Curve 发射平台 · 本地全栈演示</span>
        </div>
        <span className="badge chain" title="Foundry anvil 本地链">⚡ Anvil · 31337</span>
      </div>
      <div className="wallet-area">
        {error && <span className="error-text">{error}</span>}
        {address ? (
          <div className="wallet-box" title={address}>
            <span className="badge">{kind === 'dev' ? '🧪 Dev 钱包' : '🦊 MetaMask'}</span>
            <button className="addr" onClick={onCopy} title="点击复制完整地址">
              {shortAddr(address)}
            </button>
            {ethBalance !== null && (
              <span className="balance" title="ETH 余额">
                {ethBalance} ETH
              </span>
            )}
            <span
              className={`dot ${jwt ? 'ok' : ''}`}
              title={jwt ? 'API 已登录 (JWT)' : 'API 未登录'}
            />
            <button className="btn ghost sm" onClick={disconnect}>
              断开
            </button>
          </div>
        ) : (
          <>
            <button
              className="btn primary"
              disabled={busy}
              onClick={() => connect('injected')}
            >
              连接 MetaMask
            </button>
            <button
              className="btn"
              disabled={busy}
              onClick={() => connect('dev')}
              title="使用 anvil 预置账户，仅本地演示"
            >
              🧪 Dev 钱包
            </button>
          </>
        )}
      </div>
    </header>
  )
}
