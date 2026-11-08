import { useCallback, useEffect, useState } from 'react'
import { formatEther, parseEther } from 'ethers'
import type { TokenListItem, TradeListData } from '../lib/api'
import { getTradeList } from '../lib/api'
import {
  applyFee,
  buyTokens,
  getCurve,
  getFees,
  getTokenInfo,
  quoteBuy,
  quoteSell,
  sellTokens,
  type Curve,
  type TokenInfo,
} from '../lib/chain'
import { useWallet } from '../lib/wallet'
import KlineChart from './KlineChart'
import { useToast } from './Toast'
import { copyText, formatNum, formatPrice, shortAddr, timeAgo, weiToNumber } from '../utils/format'

/** 当前曲线价格：1 代币 = 多少 ETH（虚拟储备比） */
function curvePrice(c: Curve): number {
  if (c.virtualTokenReserve === 0n) return 0
  return (
    Number(c.virtualBNBReserve) / 1e18 /
    (Number(c.virtualTokenReserve) / 1e18)
  )
}

export default function TradePanel({
  token,
  onClose,
  onTraded,
}: {
  token: TokenListItem
  onClose: () => void
  onTraded: () => void
}) {
  const { address, signer } = useWallet()
  const { push } = useToast()
  const [curve, setCurve] = useState<Curve | null>(null)
  const [info, setInfo] = useState<TokenInfo | null>(null)
  const [feeBps, setFeeBps] = useState(100n)
  const [buyAmount, setBuyAmount] = useState('0.1')
  const [sellAmount, setSellAmount] = useState('')
  const [busy, setBusy] = useState(false)
  const [trades, setTrades] = useState<TradeListData['result']>([])

  const refresh = useCallback(async () => {
    try {
      setCurve(await getCurve(token.tokenAddr))
      if (address) setInfo(await getTokenInfo(token.tokenAddr, address))
    } catch {
      /* 代币可能尚未完成索引，忽略瞬时错误 */
    }
  }, [token.tokenAddr, address])

  useEffect(() => {
    getFees().then((f) => setFeeBps(f.tradingFeeBps)).catch(() => undefined)
    refresh()
    const timer = setInterval(refresh, 5000)
    return () => clearInterval(timer)
  }, [refresh])

  useEffect(() => {
    let alive = true
    const load = () =>
      getTradeList(token.tokenAddr, 8)
        .then((d) => alive && setTrades(d.result ?? []))
        .catch(() => undefined)
    load()
    const timer = setInterval(load, 5000)
    return () => {
      alive = false
      clearInterval(timer)
    }
  }, [token.tokenAddr])

  const buyQuote =
    curve && buyAmount ? quoteBuy(applyFee(parseEther(buyAmount), feeBps), curve) : 0n
  const sellQuote =
    curve && sellAmount ? applyFee(quoteSell(parseEther(sellAmount), curve), feeBps) : 0n

  async function doBuy() {
    if (!signer || !curve) return
    setBusy(true)
    push('info', '买入交易已发送…')
    try {
      const hash = await buyTokens(signer, token.tokenAddr, buyAmount, curve, feeBps)
      push('success', `买入成功 ${buyAmount} ETH → ${formatNum(weiToNumber(buyQuote.toString()))} ${token.symbol}`)
      void hash
      await refresh()
      onTraded()
    } catch (e) {
      push('error', `买入失败：${(e instanceof Error ? e.message : String(e)).slice(0, 90)}`)
    } finally {
      setBusy(false)
    }
  }

  async function doSell() {
    if (!signer || !curve) return
    setBusy(true)
    push('info', '卖出交易已发送（必要时先 approve）…')
    try {
      await sellTokens(signer, token.tokenAddr, sellAmount, curve, feeBps)
      push('success', `卖出成功 ${formatNum(parseFloat(sellAmount))} ${token.symbol}`)
      setSellAmount('')
      await refresh()
      onTraded()
    } catch (e) {
      push('error', `卖出失败：${(e instanceof Error ? e.message : String(e)).slice(0, 90)}`)
    } finally {
      setBusy(false)
    }
  }

  async function onCopyAddr() {
    if (await copyText(token.tokenAddr)) push('info', '代币地址已复制')
  }

  return (
    <div className="modal-mask" onClick={onClose}>
      <div className="card modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-head">
          <span className="token-logo lg">{token.logo || '🪙'}</span>
          <div className="modal-title">
            <h2>
              {token.symbol} <small>{token.name}</small>
            </h2>
            <button className="addr clickable" onClick={onCopyAddr} title="点击复制">
              {shortAddr(token.tokenAddr, 12, 8)}
            </button>
          </div>
          <button className="btn ghost sm" onClick={onClose}>
            ✕
          </button>
        </div>

        {curve ? (
          <div className="stats">
            <div className="stat-main">
              <span>当前价格</span>
              <b>{formatPrice(curvePrice(curve))}</b>
            </div>
            <div>
              <span>虚拟 ETH 储备</span>
              <b>{formatEther(curve.virtualBNBReserve).slice(0, 8)}</b>
            </div>
            <div>
              <span>可售代币</span>
              <b>{formatNum(weiToNumber(curve.availableTokens.toString()), 0)}</b>
            </div>
            <div>
              <span>池内募集</span>
              <b>{formatEther(curve.collectedBNB).slice(0, 8)}</b>
            </div>
          </div>
        ) : (
          <div className="stats-loading">读取联合曲线…</div>
        )}

        <KlineChart tokenAddr={token.tokenAddr} />

        <div className="trade-box">
          <label>
            买入（ETH）
            <div className="input-row">
              <input value={buyAmount} onChange={(e) => setBuyAmount(e.target.value)} placeholder="0.1" />
              <span className="quote">
                ≈ {formatNum(weiToNumber(buyQuote.toString()))} {token.symbol}
              </span>
            </div>
          </label>
          <div className="quick-row">
            {[0.05, 0.1, 0.5, 1].map((v) => (
              <button
                key={v}
                className={`quick ${buyAmount === String(v) ? 'on' : ''}`}
                onClick={() => setBuyAmount(String(v))}
              >
                {v}
              </button>
            ))}
          </div>
          <button className="btn primary wide" disabled={busy || !curve || !signer} onClick={doBuy}>
            买入
          </button>

          <label>
            卖出（{token.symbol}）
            <div className="input-row">
              <input
                value={sellAmount}
                onChange={(e) => setSellAmount(e.target.value)}
                placeholder="代币数量"
              />
              <span className="quote">
                ≈ {formatEther(sellQuote).slice(0, 8)} ETH
              </span>
            </div>
          </label>
          {info && (
            <div className="balance-row">
              持有 <b>{formatNum(parseFloat(info.formatted))}</b> {info.symbol || token.symbol}
              <button
                className="btn ghost sm"
                onClick={() => setSellAmount(info.formatted)}
              >
                MAX
              </button>
            </div>
          )}
          <button
            className="btn danger wide"
            disabled={busy || !curve || !signer || !sellAmount}
            onClick={doSell}
          >
            卖出
          </button>
          <div className="fee-note">交易手续费 1% · 滑点保护 10%</div>
        </div>

        <div className="trades">
          <h3>最近交易（Indexer 链上同步）</h3>
          {trades.length === 0 && <div className="empty-sm">暂无交易</div>}
          {trades.map((t) => (
            <div key={t.id} className="trade-row">
              <span className={`side ${t.tradeType === 10 ? 'buy' : 'sell'}`}>
                {t.tradeType === 10 ? '买入' : '卖出'}
              </span>
              <span>
                {formatNum(weiToNumber(t.bnbAmount), 4)} ETH ↔{' '}
                {formatNum(weiToNumber(t.tokenAmount), 0)} {token.symbol}
              </span>
              <span className="hash" title={t.transactionHash}>
                {shortAddr(t.transactionHash, 8, 6)}
              </span>
              <span className="time">{timeAgo(t.createdAt)}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
