import { useCallback, useEffect, useState } from 'react';

const API = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

type Quest = {
  code: string;
  name: string;
  description: string;
  questType: string;
  objectiveType: string;
  targetCount: number;
  progress: number;
  status: string;
  reward: { silver: number; gems: number; items: { itemId: string; quantity: number }[] };
};

type Achievement = {
  code: string;
  name: string;
  description: string;
  category: string;
  metric: string;
  threshold: number;
  progress: number;
  reward: { silver: number; gems: number; items: { itemId: string; quantity: number }[] };
  unlocked: boolean;
  claimed: boolean;
};

type QuestOverview = {
  periods: { daily: string; weekly: string };
  main: Quest[];
  side: Quest[];
  availableSide: Omit<Quest, 'progress' | 'status'>[];
  daily: Quest[];
  weekly: Quest[];
  summary: { completed: number; claimed: number; dailyTarget: number };
  achievements: Achievement[];
};

async function call<T>(path: string, token: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API}${path}`, {
    ...init,
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}`, ...init?.headers },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error((body as { error?: string }).error ?? `API error ${response.status}`);
  return body as T;
}

const numberFormat = new Intl.NumberFormat('vi-VN');

const rewardLabel = (reward: Quest['reward']) => {
  const parts: string[] = [];
  if (reward.silver) parts.push(`${numberFormat.format(reward.silver)} Xu`);
  if (reward.gems) parts.push(`${reward.gems} Ngọc`);
  for (const item of reward.items) parts.push(`${item.quantity} × ${item.itemId}`);
  return parts.length ? parts.join(' · ') : 'Không thưởng';
};

export function QuestPage({ token, onError, onNotice }: { token: string; onError: (message: string) => void; onNotice: (message: string) => void }) {
  const [data, setData] = useState<QuestOverview | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setData(await call<QuestOverview>('/api/quests', token));
  }, [token]);

  useEffect(() => { load().catch(error => onError((error as Error).message)); }, [load, onError]);

  const run = async (action: () => Promise<unknown>, message: string) => {
    setBusy(true);
    onError('');
    try {
      await action();
      await load();
      onNotice(message);
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  if (!data) return <section className="panel"><div className="empty-state"><p>Đang tải nhiệm vụ…</p></div></section>;

  const renderQuest = (quest: Quest) => {
    const percent = Math.min(100, Math.round((quest.progress / Math.max(1, quest.targetCount)) * 100));
    const claimable = quest.status === 'COMPLETED';
    return <article className="quest-row" key={`${quest.code}-${quest.questType}`}>
      <div className="quest-main">
        <b>{quest.name}</b>
        <small>{quest.description}</small>
      </div>
      <div className="quest-meter">
        <span>{quest.progress} / {quest.targetCount}</span>
        <div className="survival-bar"><i style={{ width: `${percent}%` }} /></div>
      </div>
      <div className="quest-reward">{rewardLabel(quest.reward)}</div>
      <div className="quest-action">
        {quest.status === 'CLAIMED'
          ? <em className="admin-badge ok">Đã nhận</em>
          : claimable
            ? <button type="button" className="secondary-button" disabled={busy} onClick={() => void run(() => call(`/api/quests/${quest.code}/claim`, token, { method: 'POST' }), `Đã nhận thưởng: ${quest.name}`)}>Nhận thưởng</button>
            : <em className="admin-badge">Đang làm</em>}
      </div>
    </article>;
  };

  return <>
    <div className="page-heading">
      <div>
        <div className="eyebrow">QUESTS · PHASE 1</div>
        <h1>Nhiệm vụ & Thành tựu</h1>
        <p>Nhiệm vụ chính, nhiệm vụ phụ, chu kỳ ngày/tuần và thành tựu trọn đời.</p>
      </div>
      <div className="date-chip"><span className="date-icon">◷</span><span><b>Chu kỳ</b><small>{data.periods.daily} · {data.periods.weekly}</small></span></div>
    </div>

    <div className="stat-grid">
      <div className="stat-card"><span className="stat-icon gold">✦</span><div><small>Hoàn thành</small><b>{data.summary.completed}</b><span>có thể nhận thưởng</span></div></div>
      <div className="stat-card"><span className="stat-icon blue">✓</span><div><small>Đã nhận</small><b>{data.summary.claimed}</b><span>trong kỳ hiện tại</span></div></div>
      <div className="stat-card"><span className="stat-icon violet">☀</span><div><small>Nhiệm vụ ngày</small><b>{data.daily.length} / {data.summary.dailyTarget}</b><span>reset 00:00 UTC+7</span></div></div>
      <div className="stat-card"><span className="stat-icon rose">★</span><div><small>Thành tựu mở</small><b>{data.achievements.filter(row => row.unlocked && !row.claimed).length}</b><span>chờ nhận thưởng</span></div></div>
    </div>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">MAIN & SIDE</div><h2>Nhiệm vụ chính & phụ</h2></div></div>
      <div className="quest-list">
        {data.main.map(renderQuest)}
        {data.side.map(renderQuest)}
        {data.availableSide.map(quest => <article className="quest-row" key={quest.code}>
          <div className="quest-main"><b>{quest.name}</b><small>{quest.description}</small></div>
          <div className="quest-meter"><span>0 / {quest.targetCount}</span><div className="survival-bar"><i style={{ width: '0%' }} /></div></div>
          <div className="quest-reward">{rewardLabel(quest.reward as Quest['reward'])}</div>
          <div className="quest-action"><button type="button" className="text-button" disabled={busy} onClick={() => void run(() => call(`/api/quests/${quest.code}/accept`, token, { method: 'POST' }), `Đã nhận: ${quest.name}`)}>Nhận nhiệm vụ</button></div>
        </article>)}
      </div>
    </section>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">DAILY</div><h2>Nhiệm vụ ngày</h2></div><span className="sample-tag">{data.periods.daily}</span></div>
      <div className="quest-list">{data.daily.map(renderQuest)}</div>
    </section>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">WEEKLY</div><h2>Nhiệm vụ tuần</h2></div><span className="sample-tag">{data.periods.weekly}</span></div>
      <div className="quest-list">{data.weekly.map(renderQuest)}</div>
    </section>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">ACHIEVEMENTS</div><h2>Thành tựu trọn đời</h2></div></div>
      <div className="admin-table">
        <div className="admin-row admin-row-head"><span>Thành tựu</span><span>Tiến độ</span><span>Thưởng</span><span>Trạng thái</span><span /></div>
        {data.achievements.map(row => <div className="admin-row" key={row.code}>
          <span>{row.name}<small className="admin-muted">{row.description}</small></span>
          <span>{Math.min(row.progress, row.threshold)} / {row.threshold}</span>
          <span>{rewardLabel(row.reward as Quest['reward'])}</span>
          <span>{row.claimed ? <em className="admin-badge ok">Đã nhận</em> : row.unlocked ? <em className="admin-badge warn">Mở khoá</em> : <em className="admin-badge">Chưa đạt</em>}</span>
          <span>{row.unlocked && !row.claimed && <button type="button" className="secondary-button" disabled={busy} onClick={() => void run(() => call(`/api/achievements/${row.code}/claim`, token, { method: 'POST' }), `Đã nhận thành tựu: ${row.name}`)}>Nhận</button>}</span>
        </div>)}
      </div>
    </section>
  </>;
}
