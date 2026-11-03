import { useCallback, useEffect, useState } from 'react';

const API = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

type Injury = { id: string; heroId: string; heroName: string; hp: number; maxHp: number; severity: string; penaltyPercent: number; naturalHealAt: string; attackMultiplier: number };
type Treatment = { id: string; heroId: string; heroName: string; treatmentType: string; status: string; startedAt: string; finishesAt: string | null; completedAt: string | null; costSilver: string };
type ResurrectionRow = { heroId: string; name: string; category: string; tears: number; silver: number; cycleCount: number; tearsOwned: number; affordable: boolean };

type MedicalOverview = {
  facility: { buildingId: string; level: number; capacity: number; bedsUsed: number; bedsFree: number } | null;
  capacity: number;
  bedsUsed: number;
  injuries: Injury[];
  treatments: Treatment[];
  activeTreatments: Treatment[];
  resurrection: ResurrectionRow[];
  medicineStored: number;
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

const severityLabel: Record<string, string> = { MINOR: 'Nhẹ', MODERATE: 'Trung bình', SEVERE: 'Nặng' };
const numberFormat = new Intl.NumberFormat('vi-VN');
const when = (value: string | null) => value ? new Date(value).toLocaleString('vi-VN') : '—';

export function MedicalPage({ token, onError, onNotice }: { token: string; onError: (message: string) => void; onNotice: (message: string) => void }) {
  const [data, setData] = useState<MedicalOverview | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setData(await call<MedicalOverview>('/api/medical', token));
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

  if (!data) return <section className="panel"><div className="empty-state"><p>Đang tải dữ liệu y tế…</p></div></section>;

  const facility = data.facility;

  return <>
    <div className="page-heading">
      <div>
        <div className="eyebrow">MEDICAL · PHASE 1</div>
        <h1>Viện Y Tế</h1>
        <p>Chẩn đoán thương tích, điều trị hồi phục và hồi sinh Hero Limited/Special bằng Thần Cứu Trợ.</p>
      </div>
    </div>

    <div className="stat-grid">
      <div className="stat-card"><span className="stat-icon violet">✚</span><div><small>Cơ sở</small><b>{facility ? `Cấp ${facility.level}` : 'Chưa xây'}</b><span>{facility ? `${facility.bedsUsed}/${facility.capacity} giường` : 'cần công trình Medical'}</span></div></div>
      <div className="stat-card"><span className="stat-icon rose">⚕</span><div><small>Đang thương tích</small><b>{data.injuries.length}</b><span>giảm tối đa 25% ATK/DEF</span></div></div>
      <div className="stat-card"><span className="stat-icon blue">☾</span><div><small>Đang điều trị</small><b>{data.activeTreatments.length}</b><span>{facility ? `${facility.bedsFree} giường trống` : 'chưa có cơ sở'}</span></div></div>
      <div className="stat-card"><span className="stat-icon gold">✧</span><div><small>Thuốc khẩn cấp</small><b>{data.medicineStored}</b><span>MEDICINE trong kho</span></div></div>
    </div>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">INJURIES</div><h2>Thương tích đang hoạt động</h2></div></div>
      {data.injuries.length === 0
        ? <p className="base-note">Không có Hero nào bị thương. Thương tích xuất hiện khi Hero sống sót với HP dưới 50% sau trận đánh.</p>
        : <div className="admin-table">
          <div className="admin-row admin-row-head"><span>Hero</span><span>Mức độ</span><span>Giảm chỉ số</span><span>Tự hồi</span><span>Hành động</span></div>
          {data.injuries.map(injury => <div className="admin-row" key={injury.id}>
            <span>{injury.heroName}<small className="admin-muted">HP {injury.hp}/{injury.maxHp}</small></span>
            <span><em className={`admin-badge ${injury.severity === 'SEVERE' ? 'danger' : injury.severity === 'MODERATE' ? 'warn' : 'ok'}`}>{severityLabel[injury.severity] ?? injury.severity}</em></span>
            <span>−{injury.penaltyPercent}%</span>
            <span>{when(injury.naturalHealAt)}</span>
            <span className="admin-actions">
              <button type="button" className="secondary-button" disabled={busy || !facility} onClick={() => void run(() => call('/api/medical/treatments', token, { method: 'POST', body: JSON.stringify({ heroId: injury.heroId }) }), 'Đã tiếp nhận điều trị.')}>Nhập viện</button>
              <button type="button" className="text-button" disabled={busy || data.medicineStored < 1} onClick={() => void run(() => call('/api/medical/emergency', token, { method: 'POST', body: JSON.stringify({ heroId: injury.heroId }) }), 'Đã chữa trị khẩn cấp.')}>Khẩn cấp</button>
            </span>
          </div>)}
        </div>}
    </section>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">DIVINE GRACE</div><h2>Hồi sinh</h2></div></div>
      {data.resurrection.length === 0
        ? <p className="base-note">Không có Hero nào đang ở trạng thái Disabled.</p>
        : <div className="admin-table">
          <div className="admin-row admin-row-head"><span>Hero</span><span>Loại</span><span>Chi phí</span><span>Chu kỳ</span><span>Hành động</span></div>
          {data.resurrection.map(row => <div className="admin-row" key={row.heroId}>
            <span>{row.name}</span>
            <span>{row.category}</span>
            <span>{row.tears} × DIVINE_TEAR · {numberFormat.format(row.silver)} Xu<small className="admin-muted">đang có {row.tearsOwned} lệ</small></span>
            <span>lần {row.cycleCount + 1}<small className="admin-muted">reset sau 30 ngày</small></span>
            <span><button type="button" className="secondary-button" disabled={busy || !row.affordable} onClick={() => void run(() => call('/api/medical/resurrect', token, { method: 'POST', body: JSON.stringify({ heroId: row.heroId }) }), 'Hero đã hồi sinh.')}>Hồi sinh</button></span>
          </div>)}
        </div>}
    </section>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">HISTORY</div><h2>Lịch sử điều trị</h2></div></div>
      <div className="admin-table">
        <div className="admin-row admin-row-head"><span>Hero</span><span>Loại</span><span>Trạng thái</span><span>Bắt đầu</span><span>Hoàn tất</span></div>
        {data.treatments.length === 0 && <div className="admin-row"><span>Chưa có bản ghi.</span></div>}
        {data.treatments.slice(0, 12).map(row => <div className="admin-row" key={row.id}>
          <span>{row.heroName}</span>
          <span>{row.treatmentType}</span>
          <span><em className={`admin-badge ${row.status === 'COMPLETED' ? 'ok' : 'warn'}`}>{row.status}</em></span>
          <span>{when(row.startedAt)}</span>
          <span>{when(row.completedAt)}</span>
        </div>)}
      </div>
    </section>
  </>;
}
