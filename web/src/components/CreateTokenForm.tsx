import { useEffect, useState } from 'react'
import { formatEther } from 'ethers'
import { createToken, type CreateTokenForm as CreateForm } from '../lib/api'
import { createTokenOnChain, getFees } from '../lib/chain'
import { useWallet } from '../lib/wallet'
import { useToast } from './Toast'

const EMPTY: CreateForm = {
  name: '',
  symbol: '',
  description: '',
  logo: '🐕',
  launchMode: 1,
  launchTime: 0,
  preBuyPercent: 0,
  marginBnb: 0,
  marginTime: 0,
}

const EMOJI_PRESETS = ['🐕', '🐱', '🐸', '🦍', '🚀', '💎', '🌙', '🔥']

export default function CreateTokenForm({ onCreated }: { onCreated: () => void }) {
  const { address, signer, ensureLogin } = useWallet()
  const { push } = useToast()
  const [form, setForm] = useState(EMPTY)
  const [step, setStep] = useState(0) // 0 空闲 1..3 进行中 4 完成
  const [busy, setBusy] = useState(false)
  const [log, setLog] = useState<string[]>([])
  const [creationFee, setCreationFee] = useState<string>('0.05')

  useEffect(() => {
    getFees()
      .then((f) => setCreationFee(formatEther(f.creationFee)))
      .catch(() => undefined)
  }, [])

  const append = (line: string) => setLog((prev) => [...prev.slice(-5), line])

  const set =
    (key: keyof CreateForm) =>
    (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
      setForm((prev) => ({ ...prev, [key]: e.target.value }))

  async function submit() {
    if (!address || !signer) {
      push('error', '请先连接钱包')
      return
    }
    if (!form.name.trim() || !form.symbol.trim()) {
      push('error', '请填写代币名称和符号')
      return
    }
    setBusy(true)
    setLog([])
    try {
      setStep(1)
      append('① SIWE 钱包签名登录…')
      const jwt = await ensureLogin()

      setStep(2)
      append('② 提交发币参数，获取后端 ECDSA 签名…')
      const data = await createToken(
        { ...form, launchTime: Math.floor(Date.now() / 1000) },
        jwt,
      )
      append(`   预测地址(CREATE2): ${data.predictedAddress}`)

      setStep(3)
      append('③ 链上调用 Core.createToken（支付创建费）…')
      const fees = await getFees()
      const { hash, tokenAddress } = await createTokenOnChain(
        signer,
        data.createArg,
        data.signature,
        fees.creationFee,
      )
      append(`   交易: ${hash.slice(0, 20)}…`)
      setStep(4)
      append(
        tokenAddress
          ? `✅ 发币成功！合约地址: ${tokenAddress}`
          : '✅ 交易成功，等待索引器同步',
      )
      push('success', `代币 ${form.symbol} 发射成功 🎉`)
      setForm({ ...EMPTY, logo: form.logo })
      onCreated()
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e)
      append(`❌ ${msg}`)
      push('error', `发币失败：${msg.slice(0, 80)}`)
    } finally {
      setBusy(false)
      setTimeout(() => setStep(0), 1500)
    }
  }

  return (
    <section className="card create-card">
      <h2>
        发射代币 <span className="h-sub">公平发射 · 无预买</span>
      </h2>

      <label>
        代币名称
        <input placeholder="Anvil Doge" value={form.name} onChange={set('name')} />
      </label>
      <label>
        代币符号
        <div className="symbol-row">
          <input
            placeholder="ADOGE"
            value={form.symbol}
            onChange={(e) =>
              setForm((p) => ({ ...p, symbol: e.target.value.toUpperCase() }))
            }
          />
          <span className="chars">{form.symbol.length}/16</span>
        </div>
      </label>
      <div className="emoji-row">
        {EMOJI_PRESETS.map((e) => (
          <button
            key={e}
            type="button"
            className={`emoji ${form.logo === e ? 'on' : ''}`}
            onClick={() => setForm((p) => ({ ...p, logo: e }))}
          >
            {e}
          </button>
        ))}
        <input
          className="emoji-input"
          value={EMOJI_PRESETS.includes(form.logo) ? '' : form.logo}
          onChange={set('logo')}
          placeholder="自定义"
          maxLength={4}
        />
      </div>
      <label>
        简介
        <textarea
          rows={2}
          placeholder="一句话介绍你的 meme 币"
          value={form.description}
          onChange={set('description')}
        />
      </label>

      <div className="fee-tip">
        创建费 <b>{creationFee}</b> ETH · 联合曲线内盘 · 毕业自动加池销毁 LP
      </div>
      <button className="btn primary wide lg" disabled={busy} onClick={submit}>
        {busy ? `执行中 (${step}/3)…` : '🚀 发射代币'}
      </button>

      {log.length > 0 && (
        <div className={`log ${step === 4 ? 'ok' : ''}`}>
          {log.map((line, i) => (
            <div key={i}>{line}</div>
          ))}
        </div>
      )}
      {!address && <div className="hint">先连接钱包才能发射</div>}
    </section>
  )
}
