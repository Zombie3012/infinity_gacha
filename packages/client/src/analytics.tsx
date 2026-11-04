import { useCallback, useEffect, useState } from 'react';

const API = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

type Summary = {
  generatedAt: string;
  players: { accounts: number; masters: number; activeAccounts7d: number; newAccounts7d: number; restrictedAccounts: number; masterConversion: { rate: number } };
  gacha: { totalRolls: number; fiveStarRate: { rate: number }; duplicateRate: { rate: number }; averagePityAtFiveStar: number; last7d: { rolls: number; fiveStars: number; rate: { rate: number } } };
  economy: { flows: { currencyType: string; inflow: string; outflow: string; entries: number }[]; payments: { completed: number; refunded: number; revenueUsd: number; refundRate: { rate: number } }; outstandingGemDebt: number };
  battle: { completed: number; victories: number; defeats: number; winRate: { rate: number }; averageRounds: number; heroDeaths: number; heroDeaths7d: number; active: number };
  retention: { activeThisWeek: number; activePreviousWeek: number; returningPlayers: number; weekOverWeekRetention: { rate: number } };
};

async function adminFetch<T>(key: string, path: string): Promise<T> {
  const response = await fetch(`${API}${path}`, { headers: { 'x-admin-api-key': key } });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error((body as { error?: string }).error ?? `API error ${response.status}`);
  return body as T;
}

const pct = (rate: number) => `${(rate * 100).toFixed(2)}%`;
const numberFormat = new Intl.NumberFormat('vi-VN');

export function AnalyticsPanel({ adminKey, onError }: { adminKey: string; onError: (message: string) => void }) {
  const [data, setData] = useState<Summary | null>(null);

  const load = useCallback(async () => {
    setData(await adminFetch<Summary>(adminKey, '/api/admin/analytics'));
  }, [adminKey]);

  useEffect(() => { load().catch(error => onError((error as Error).message)); }, [load, onError]);

  if (!data) return <section className="panel"><div className="empty-state"><p>Đang tải phân tích…</p></div></section>;

  return <>
    <section className="panel">
      <div className="panel-head">
        <div><div className="eyebrow">ANALYTICS</div><h2>Tổng quan vận hành</h2></div>
        <button type="button" className="secondary-button" onClick={() => void load().catch(error => onError((error as Error).message))}>Làm mới</button>
      </div>
      <div className="stat-grid">
        <div className="stat-card"><span className="stat-icon gold">◈</span><div><small>Tài khoản</small><b>{numberFormat.format(data.players.accounts)}</b><span>{data.players.masters} Master · {data.players.restrictedAccounts} bị hạn chế</span></div></div>
        <div className="stat-card"><span className="stat-icon blue">☰</span><div><small>Hoạt động 7 ngày</small><b>{numberFormat.format(data.players.activeAccounts7d)}</b><span>mới: {numberFormat.format(data.players.newAccounts7d)}</span></div></div>
        <div className="stat-card"><span className="stat-icon violet">✦</span><div><small>Tỷ lệ 5★</small><b>{pct(data.gacha.fiveStarRate.rate)}</b><span>{numberFormat.format(data.gacha.totalRolls)} lượt · pity TB {data.gacha.averagePityAtFiveStar}</span></div></div>
        <div className="stat-card"><span className="stat-icon rose">⚔</span><div><small>Tỷ lệ thắng</small><b>{pct(data.battle.winRate.rate)}</b><span>{data.battle.victories} thắng / {data.battle.defeats} thua</span></div></div>
      </div>
    </section>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">ECONOMY</div><h2>Dòng tiền</h2></div></div>
      <div className="admin-table">
        <div className="admin-row admin-row-head"><span>Loại tiền</span><span>Vào</span><span>Ra</span><span>Số bút toán</span><span /></div>
        {data.economy.flows.length === 0 && <div className="admin-row"><span>Chưa có giao dịch tiền tệ.</span></div>}
        {data.economy.flows.map(row => <div className="admin-row" key={row.currencyType}>
          <span>{row.currencyType}</span>
          <span>{numberFormat.format(Number(row.inflow))}</span>
          <span>{numberFormat.format(Number(row.outflow))}</span>
          <span>{row.entries}</span>
          <span />
        </div>)}
      </div>
      <p className="base-note">
        Doanh thu IAP: ${data.economy.payments.revenueUsd.toFixed(2)} ({data.economy.payments.completed} giao dịch, {data.economy.payments.refunded} hoàn tiền,
        {' '}tỷ lệ hoàn {pct(data.economy.payments.refundRate.rate)}) · Nợ Ngọc tồn: {numberFormat.format(data.economy.outstandingGemDebt)}
      </p>
    </section>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">RETENTION</div><h2>Giữ chân người chơi</h2></div></div>
      <div className="admin-table">
        <div className="admin-row admin-row-head"><span>Tuần này</span><span>Tuần trước</span><span>Quay lại</span><span>Tỷ lệ tuần</span><span>Hero tử vong 7d</span></div>
        <div className="admin-row">
          <span>{data.retention.activeThisWeek}</span>
          <span>{data.retention.activePreviousWeek}</span>
          <span>{data.retention.returningPlayers}</span>
          <span>{pct(data.retention.weekOverWeekRetention.rate)}</span>
          <span>{data.battle.heroDeaths7d} / {data.battle.heroDeaths}</span>
        </div>
      </div>
      <p className="base-note">Số vòng trung bình mỗi trận: {data.battle.averageRounds} · phiên đang mở: {data.battle.active}</p>
    </section>
  </>;
}
