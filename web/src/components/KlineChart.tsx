import { useEffect, useRef, useState } from 'react'
import {
  CandlestickSeries,
  ColorType,
  HistogramSeries,
  createChart,
  type IChartApi,
  type ISeriesApi,
  type UTCTimestamp,
} from 'lightweight-charts'
import { getKlineHistory } from '../lib/api'
import { weiToNumber } from '../utils/format'

const INTERVALS = ['1m', '5m', '15m', '1h', '4h', '1d'] as const
const LOOKBACK_MS: Record<string, number> = {
  '1m': 2 * 3600_000,
  '5m': 8 * 3600_000,
  '15m': 24 * 3600_000,
  '1h': 3 * 86400_000,
  '4h': 7 * 86400_000,
  '1d': 30 * 86400_000,
}

/**
 * 联合曲线交易 K 线图（蜡烛 + 成交量）
 * 数据来自 Go API /kline/history，由 Indexer 从链上 TokenBought/Sold 事件实时聚合
 */
export default function KlineChart({ tokenAddr }: { tokenAddr: string }) {
  const container = useRef<HTMLDivElement>(null)
  const chart = useRef<IChartApi | null>(null)
  const candle = useRef<ISeriesApi<'Candlestick'> | null>(null)
  const volume = useRef<ISeriesApi<'Histogram'> | null>(null)
  const [interval, setInterval_] = useState<string>('1m')
  const [empty, setEmpty] = useState(false)

  // 初始化图表（一次）
  useEffect(() => {
    if (!container.current) return
    const c = createChart(container.current, {
      layout: {
        background: { type: ColorType.Solid, color: 'transparent' },
        textColor: '#7c8798',
        fontSize: 11,
      },
      grid: {
        vertLines: { color: 'rgba(35,44,61,0.5)' },
        horzLines: { color: 'rgba(35,44,61,0.5)' },
      },
      rightPriceScale: { borderColor: '#232c3d' },
      timeScale: { borderColor: '#232c3d', timeVisible: true, secondsVisible: false },
      autoSize: true,
    })
    candle.current = c.addSeries(CandlestickSeries, {
      upColor: '#22c55e',
      downColor: '#ef4444',
      wickUpColor: '#22c55e',
      wickDownColor: '#ef4444',
      borderVisible: false,
    })
    volume.current = c.addSeries(HistogramSeries, {
      priceScaleId: '',
      priceFormat: { type: 'volume' },
      color: 'rgba(240,185,11,0.35)',
    })
    // 成交量柱压在底部 20% 高度
    volume.current.priceScale().applyOptions({
      scaleMargins: { top: 0.85, bottom: 0 },
    })
    chart.current = c
    return () => {
      c.remove()
      chart.current = null
    }
  }, [])

  // 拉取数据 + 每 5s 刷新
  useEffect(() => {
    let alive = true
    async function load() {
      try {
        const to = Math.floor(Date.now() / 1000)
        const from = Math.floor((Date.now() - LOOKBACK_MS[interval]) / 1000)
        const d = await getKlineHistory(tokenAddr, interval, from, to)
        if (!alive || !candle.current || !volume.current) return
        const rows = (d.t ?? []).map((t, i) => ({
          time: t as UTCTimestamp,
          open: parseFloat(d.o[i]),
          high: parseFloat(d.h[i]),
          low: parseFloat(d.l[i]),
          close: parseFloat(d.c[i]),
        }))
        const vols = (d.t ?? []).map((t, i) => ({
          time: t as UTCTimestamp,
          value: weiToNumber(d.v[i]),
          color:
            parseFloat(d.c[i]) >= parseFloat(d.o[i])
              ? 'rgba(34,197,94,0.35)'
              : 'rgba(239,68,68,0.35)',
        }))
        candle.current.setData(rows)
        volume.current.setData(vols)
        setEmpty(rows.length === 0)
        chart.current?.timeScale().fitContent()
      } catch {
        /* 数据暂未生成时静默 */
      }
    }
    load()
    const timer = setInterval(load, 5000)
    return () => {
      alive = false
      clearInterval(timer)
    }
  }, [tokenAddr, interval])

  return (
    <div className="kline-box">
      <div className="kline-toolbar">
        <span className="kline-title">价格走势</span>
        <div className="kline-tabs">
          {INTERVALS.map((iv) => (
            <button
              key={iv}
              className={`kline-tab ${interval === iv ? 'on' : ''}`}
              onClick={() => setInterval_(iv)}
            >
              {iv}
            </button>
          ))}
        </div>
      </div>
      <div ref={container} className="kline-container" />
      {empty && (
        <div className="kline-empty">暂无成交 K 线 —— 买一笔立即生成 📈</div>
      )}
    </div>
  )
}
