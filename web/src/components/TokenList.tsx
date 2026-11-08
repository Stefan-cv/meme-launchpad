import { useMemo, useState } from 'react'
import { usePolling } from '../hooks/usePolling'
import { getTokenList, type TokenListItem } from '../lib/api'
import { formatEth, formatNum, isLogoUrl, weiToNumber } from '../utils/format'

type SortKey = 'latest' | 'progress' | 'name'

export default function TokenList({
  refreshKey,
  onSelect,
  selected,
}: {
  refreshKey: number
  onSelect: (t: TokenListItem) => void
  selected?: string
}) {
  const [keyword, setKeyword] = useState('')
  const [sort, setSort] = useState<SortKey>('latest')
  const { data, error } = usePolling(() => getTokenList(1, 60), 5000, [refreshKey])

  const items = useMemo(() => {
    const list = data?.result ?? []
    const kw = keyword.trim().toLowerCase()
    const filtered = kw
      ? list.filter(
          (t) =>
            t.symbol.toLowerCase().includes(kw) ||
            t.name.toLowerCase().includes(kw) ||
            t.tokenAddr.toLowerCase().includes(kw),
        )
      : list
    return [...filtered].sort((a, b) => {
      if (sort === 'progress')
        return weiToNumber(b.currentBnb) - weiToNumber(a.currentBnb)
      if (sort === 'name') return a.symbol.localeCompare(b.symbol)
      return new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
    })
  }, [data, keyword, sort])

  return (
    <section className="list-wrap">
      <div className="list-head">
        <h2>
          代币市场{' '}
          <span className="total-badge">{data?.total ?? '…'}</span>
        </h2>
        <div className="list-tools">
          <div className="sort-tabs">
            {(
              [
                ['latest', '最新'],
                ['progress', '募资'],
                ['name', '名称'],
              ] as [SortKey, string][]
            ).map(([k, label]) => (
              <button
                key={k}
                className={`sort-tab ${sort === k ? 'on' : ''}`}
                onClick={() => setSort(k)}
              >
                {label}
              </button>
            ))}
          </div>
          <input
            className="search"
            placeholder="搜索名称 / 符号 / 地址…"
            value={keyword}
            onChange={(e) => setKeyword(e.target.value)}
          />
        </div>
      </div>

      <div className="live-row">
        <span className="live-dot" />
        <span>Indexer 每 5s 同步链上事件 · 新代币发射后自动出现在列表</span>
      </div>

      {error && <div className="error-text">列表加载失败: {error}</div>}
      <div className="grid">
        {items.map((t) => (
          <button
            key={t.id}
            className={`card token-card ${selected === t.tokenAddr ? 'active' : ''}`}
            onClick={() => onSelect(t)}
          >
            <div className="token-head">
              {isLogoUrl(t.logo) ? (
                <img className="token-logo-img" src={t.logo} alt={t.symbol} />
              ) : (
                <span className="token-logo">{t.logo || '🪙'}</span>
              )}
              <div className="token-title">
                <b>{t.symbol}</b>
                <span>{t.name}</span>
              </div>
              <span className="rank">#{t.id}</span>
            </div>
            <div className="addr" title={t.tokenAddr}>
              {t.tokenAddr.slice(0, 10)}…{t.tokenAddr.slice(-8)}
            </div>
            <div className="progress">
              <div
                className="bar"
                style={{
                  width: `${Math.min(
                    100,
                    Math.max(2, parseFloat(t.progressPct) || 0),
                  )}%`,
                }}
              />
            </div>
            <div className="row">
              <span className="pct">{t.progressPct}%</span>
              <span>
                {formatEth(t.currentBnb)} / {formatNum(weiToNumber(t.targetBnb), 0)} ETH
              </span>
            </div>
            <div className="row meta">
              <span>池 {formatEth(t.currentBnb)} ETH</span>
              <span>{new Date(t.createdAt).toLocaleDateString('zh-CN')}</span>
            </div>
          </button>
        ))}
        {items.length === 0 && !error && (
          <div className="card empty">
            {keyword ? `没有匹配「${keyword}」的代币` : '暂无代币，左侧发射第一个 🚀'}
          </div>
        )}
      </div>
    </section>
  )
}
