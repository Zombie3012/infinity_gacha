import { useCallback, useEffect, useState } from 'react';

const API = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

type Recipe = {
  code: string;
  name: string;
  targetTemplateCode: string;
  targetName: string;
  requiredForgeLevel: number;
  requiredMaterials: { itemId: string; quantity: number }[];
  craftFeeSilver: number;
  forgeLevel: number;
  validation: { ok: boolean; missingMaterials: { itemId: string; quantity: number }[]; missingSilver: number; reason?: string };
};

type Equipment = {
  id: string;
  templateCode: string;
  name: string;
  slotType: string;
  rarity: number;
  starLevel: number;
  enhanceLevel: number;
  statMultiplier: number;
  substats: { hp: number; attack: number; defense: number; speed: number };
  stats: { hp: number; attack: number; defense: number; speed: number };
  upgradeCost: { stones: number; silver: number };
};

type CraftingOverview = {
  forgeLevel: number;
  silverCoins: string;
  enhancementStones: number;
  recipes: Recipe[];
  equipment: Equipment[];
  fusionRequirement: number;
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

export function CraftingPage({ token, onError, onNotice }: { token: string; onError: (message: string) => void; onNotice: (message: string) => void }) {
  const [data, setData] = useState<CraftingOverview | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setData(await call<CraftingOverview>('/api/crafting', token));
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

  const craft = (recipe: Recipe) => run(
    () => call('/api/crafting/craft', token, { method: 'POST', body: JSON.stringify({ recipeCode: recipe.code }) }),
    `Đã chế tạo ${recipe.targetName}.`,
  );

  const enhance = (item: Equipment) => run(
    () => call(`/api/crafting/equipment/${item.id}/enhance`, token, { method: 'POST' }),
    `${item.name} lên cấp tăng cường ${item.enhanceLevel + 1}.`,
  );

  const fuse = (item: Equipment) => run(
    () => call('/api/crafting/fuse', token, { method: 'POST', body: JSON.stringify({ templateCode: item.templateCode, starLevel: item.starLevel }) }),
    `${item.name} đã dung hợp lên ${item.starLevel + 1} sao.`,
  );

  if (!data) return <section className="panel"><div className="empty-state"><p>Đang tải xưởng…</p></div></section>;

  const groups = new Map<string, Equipment[]>();
  for (const item of data.equipment) {
    const key = `${item.templateCode}:${item.starLevel}`;
    groups.set(key, [...(groups.get(key) ?? []), item]);
  }

  return <>
    <div className="page-heading">
      <div>
        <div className="eyebrow">FORGE · PHASE 1</div>
        <h1>Xưởng chế tạo</h1>
        <p>Chế tạo trang bị từ công thức, tăng cường bằng Đá Tăng Cường và dung hợp 3 món cùng loại để lên sao.</p>
      </div>
    </div>

    <div className="stat-grid">
      <div className="stat-card"><span className="stat-icon gold">⚒</span><div><small>Xưởng Rèn</small><b>{data.forgeLevel > 0 ? `Cấp ${data.forgeLevel}` : 'Chưa xây'}</b><span>cần cho công thức</span></div></div>
      <div className="stat-card"><span className="stat-icon blue">◆</span><div><small>Đá Tăng Cường</small><b>{data.enhancementStones}</b><span>dùng để nâng cấp</span></div></div>
      <div className="stat-card"><span className="stat-icon violet">▦</span><div><small>Trang bị</small><b>{data.equipment.length}</b><span>trong túi đồ</span></div></div>
      <div className="stat-card"><span className="stat-icon rose">★</span><div><small>Dung hợp</small><b>{data.fusionRequirement} món</b><span>cùng loại để +1 sao</span></div></div>
    </div>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">RECIPES</div><h2>Công thức</h2></div></div>
      <div className="admin-table">
        <div className="admin-row admin-row-head"><span>Công thức</span><span>Nguyên liệu</span><span>Phí</span><span>Điều kiện</span><span /></div>
        {data.recipes.length === 0 && <div className="admin-row"><span>Chưa có công thức.</span></div>}
        {data.recipes.map(recipe => <div className="admin-row" key={recipe.code}>
          <span>{recipe.targetName}<small className="admin-muted">Xưởng Lv.{recipe.requiredForgeLevel}</small></span>
          <span>{recipe.requiredMaterials.map(row => `${row.quantity} ${row.itemId}`).join(' · ')}</span>
          <span>{numberFormat.format(recipe.craftFeeSilver)} Xu</span>
          <span>{recipe.validation.ok
            ? <em className="admin-badge ok">Đủ điều kiện</em>
            : <em className="admin-badge warn">{recipe.validation.reason === 'ERR_CRAFT_FORGE_LEVEL' ? 'Cần Xưởng cấp cao' : recipe.validation.reason === 'ERR_CRAFT_MISSING_SILVER' ? 'Thiếu Xu' : `Thiếu ${recipe.validation.missingMaterials.map(row => row.itemId).join(', ')}`}</em>}</span>
          <span><button type="button" className="secondary-button" disabled={busy || !recipe.validation.ok} onClick={() => void craft(recipe)}>Chế tạo</button></span>
        </div>)}
      </div>
    </section>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">INVENTORY</div><h2>Trang bị trong túi</h2></div></div>
      <div className="shop-grid">
        {data.equipment.length === 0 && <div className="empty-state"><p>Chưa có trang bị nào.</p></div>}
        {data.equipment.map(item => {
          const sameGroup = groups.get(`${item.templateCode}:${item.starLevel}`) ?? [];
          return <article className="shop-card" key={item.id}>
            <header><b>{item.name}</b><em className="admin-badge">{item.starLevel}★</em></header>
            <p>+{item.enhanceLevel} cường hoá · ×{item.statMultiplier.toFixed(2)} chỉ số</p>
            <div className="shop-price">
              <span>ATK +{item.stats.attack} · DEF +{item.stats.defense}</span>
              <small>HP +{item.stats.hp} · SPD +{item.stats.speed}</small>
            </div>
            <div className="shop-actions">
              <button type="button" className="secondary-button" disabled={busy} onClick={() => void enhance(item)}>+1 ({item.upgradeCost.stones} đá · {numberFormat.format(item.upgradeCost.silver)} Xu)</button>
              {sameGroup.length >= data.fusionRequirement && <button type="button" className="text-button" disabled={busy} onClick={() => void fuse(item)}>Dung hợp</button>}
            </div>
          </article>;
        })}
      </div>
    </section>
  </>;
}
