/** 集中的数字/时间格式化工具 —— 全站展示统一走这里 */

/** wei 字符串 → ETH 数值 */
export function weiToNumber(wei: string | number | null | undefined): number {
  const n = typeof wei === 'string' ? parseFloat(wei) : (wei ?? 0)
  return n / 1e18
}

/** wei 字符串 → ETH 显示（自适应精度：>=1 保留 4 位，小数保留 6 位） */
export function formatEth(wei: string | null | undefined, digits?: number): string {
  const v = weiToNumber(wei)
  return formatNum(v, digits ?? (v >= 1 ? 4 : 6))
}

/** 数字格式化：大数千分位 + 自适应小数位 */
export function formatNum(v: number, digits = 2): string {
  if (!isFinite(v)) return '0'
  const abs = Math.abs(v)
  if (abs >= 1e9) return `${(v / 1e9).toFixed(2)}B`
  if (abs >= 1e6) return `${(v / 1e6).toFixed(2)}M`
  if (abs >= 1e3) return v.toLocaleString('zh-CN', { maximumFractionDigits: 0 })
  return v.toLocaleString('zh-CN', { maximumFractionDigits: digits })
}

/** 极小价格显示：优先有效位科学计数，如 7.7452e-9 ETH */
export function formatPrice(v: number): string {
  if (!isFinite(v) || v === 0) return '0'
  if (v >= 0.0001) return v.toPrecision(6)
  return `${v.toExponential(4)} ETH`
}

export function shortAddr(addr: string, head = 6, tail = 4): string {
  if (!addr) return ''
  return `${addr.slice(0, head)}...${addr.slice(-tail)}`
}

/** 相对时间：刚刚 / N 分钟前 / N 小时前 / 日期 */
export function timeAgo(iso: string): string {
  const t = new Date(iso).getTime()
  if (isNaN(t)) return ''
  const diff = Date.now() - t
  if (diff < 60_000) return '刚刚'
  if (diff < 3_600_000) return `${Math.floor(diff / 60_000)} 分钟前`
  if (diff < 86_400_000) return `${Math.floor(diff / 3_600_000)} 小时前`
  return new Date(t).toLocaleDateString('zh-CN')
}

/** logo 字段渲染：http(s) 开头当图片 URL，否则当 emoji/文字 */
export function isLogoUrl(logo: string | undefined): boolean {
  return !!logo && /^https?:\/\//.test(logo)
}

export async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text)
    return true
  } catch {
    return false
  }
}
