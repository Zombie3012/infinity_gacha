import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './style.css';
import { AdminPage } from './admin';
import { BasePage } from './base';
import { SurvivalPage } from './survival';
import { MedicalPage } from './medical';

const API = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';
type Session = { token: string; accountId: string; username: string };
type Master = { id: string; masterName: string; level: number; exp: string; silverCoins: string; gems: string };
type FeatureUnlock = { featureCode: string; featureName: string; requiredMasterLevel: number; unlocked: boolean };
type MasterSkill = { code: string; name: string; description: string; unlockLevel: number; durationSeconds: number; healMaxHpPercentPerSecond: number; cooldownSeconds: number };
type World = { id: string; worldSeed: string; seedAlgorithmVersion?: number; difficultyMultiplier: number; currentFloor: number; createdAt: string };
type DungeonFloorProgress = {
  id: string;
  floorNumber: number;
  name: string;
  recommendedPower: number;
  status: 'CLEARED' | 'CURRENT' | 'UNLOCKED' | 'LOCKED';
  isUnlocked: boolean;
  unlockReason?: string;
  baseRewards: { silver: number; masterExp: number };
  firstClearRewards: { silver?: number; normalScrolls?: number; specialScrolls?: number };
  isFirstClearAvailable: boolean;
};
type Me = { account: { id: string; username: string }; master: Master | null; world: World | null; summonInventory?: { scrollType: string; quantity: number }[]; itemInventory?: { itemId: string; quantity: number }[]; heroDevelopmentConfigs?: { action: string; rank: number; materialItemId: string; materialQuantity: number; requiredHeroLevel: number; requiredPromotionRank: number; maxLevelAfter: number; statGrowthMultiplier: number }[]; weeklyScrollExchange?: { periodKey: string; quantity: number; limit: number } };
type PlayerProfile = { display_name: string; avatar_url: string | null; settings: { language?: string; soundEnabled?: boolean; notificationsEnabled?: boolean }; progress_summary: { master_level: number; world_floor: number; heroes_owned: number; active_heroes: number; summons_made: number } };
type Banner = { id: string; name: string; bannerType: string; isActive: boolean; startDate: string; endDate: string | null };
type BannerDetail = { banner: Banner; pool: { rewardId: string; rewardName: string; rewardType: string; poolGroup: string; heroTemplateCode: string | null; rarity: number | null }[]; rates: { fiveStarHeroPercent: number; otherHeroPercent: number; materialPercent: number; fiveStarBasePercent: number }; pity: { currentCount: number; nextRoll: number; hardPityAt: number } };
type Roll = { rollNumber: number; itemType: 'HERO' | 'MATERIAL'; rewardName: string; rarity: number; isDuplicate: boolean };
type HeroSkill = { code: string; name: string; description: string; effectType: string; effectValue: number; skillEffectValue: number; upgradeIncrement: number; cooldownSeconds: number; unlockLevel: number; maxLevel: number; skillLevel: number; isUnlocked: boolean; behaviorMode: 'AUTO' | 'MANUAL'; canUnlock: boolean };
type Hero = { id: string; name: string; rarity: number; category: string; state: string; level: number; thienMenh: number; heroClass?: string; isLocked?: boolean; promotionRank?: number; awakeningRank?: number; maxLevel?: number; exp?: string; nextLevelExp?: string | null; skills?: HeroSkill[]; derivedStats?: { hp: number; maxHp: number; attack: number; defense: number; speed: number } };
type HeroTemplate = { id: string; code: string; name: string; defaultRarity: number; heroClass: string; element: string; baseHp: number; baseAttack: number; baseDefense: number; baseSpeed: number };
type CombatSession = {
  id: string;
  worldId: string;
  partyId?: string | null;
  status: string;
  activeBuffId: string | null;
  lastBuffChangeAt: string | null;
  cooldownUntil: string | null;
  createdAt: string;
  finishedAt: string | null;
  combatState?: {
    round: number;
    floor: number;
    difficultyMultiplier: number;
    partyId?: string | null;
    strategy?: { initialBuffId?: string | null; name?: string | null; configuredAt?: string | null } | null;
    masterSkillCooldownUntil?: string | null;
    masterSkillEffect?: { skillCode?: string; skillName: string; startedAt: string; durationSeconds: number; healPercentPerSecond?: number; appliedTicks: number } | null;
    floorEvent?: { code?: string; name: string; description: string; eventType: string };
    targetPriority?: 'LOWEST_HP' | 'HIGHEST_ATK' | 'FRONTLINE' | 'BALANCED';
    heroes: { id: string; slotIndex?: number; name: string; heroClass?: string; element?: string; hp: number; maxHp: number; shield?: number; attack?: number; defense?: number; speed?: number; critRate?: number; statusEffects?: { type: string; value: number; remainingRounds: number }[]; skills?: { skillCode: string; name: string; skillLevel: number; effectValue: number; behaviorMode: string }[] }[];
    enemies: { id: string; slotIndex?: number; name: string; element?: string; hp: number; maxHp: number; shield?: number; attack?: number; defense?: number; speed?: number; statusEffects?: { type: string; value: number; remainingRounds: number }[] }[];
    log: { round: number; actor: string; target: string; actionType?: string; skillName?: string; damage: number; heal?: number; targetHp: number; note?: string }[];
  } | null;
  battleReport?: {
    result: string;
    rounds: number;
    floor: number;
    nextFloor: number;
    floorEvent?: { name: string; description: string; eventType: string };
    expReward: number;
    masterExpReward?: number;
    masterLevelUps?: { fromLevel: number; toLevel: number }[];
    silverReward: number;
    floorEventSilverReward?: number;
    heroLevelUps?: { heroId: string; name: string; fromLevel: number; toLevel: number }[];
    survivors?: { id: string; name: string; hp: number; maxHp: number; hpPercent: number }[];
    fallenHeroes: { id: string; name: string; origin?: string; deathType: string; droppedEquipmentCount?: number }[];
    log: { round: number; actor: string; target: string; damage: number; targetHp: number }[];
  } | null;
};
type CombatPartyRow = { slotIndex: number; hero: Hero };
type Party = { id: string; name: string; isDefault: boolean; members: CombatPartyRow[] };
type InventoryItem = {
  id: string;
  itemId: string;
  name: string;
  description: string;
  category: string;
  rarity: number;
  quantity: number;
  sellPrice: number;
  canUse: boolean;
  updatedAt: string;
};
type CurrencyBalances = {
  silverCoins: string;
  summonTickets: { normal: number; special: number };
  weeklyExchange: { exchanged: number; weeklyCap: number; remainingCap: number };
};
type EquipmentRow = { equipment: { id: string; location: 'INVENTORY' | 'EQUIPPED' | 'FLOOR_DROP'; equippedHeroId: string | null; dropFloor: number | null }; template: { code: string; name: string; slotType: string; rarity: number; bonusHp: number; bonusAttack: number; bonusDefense: number; bonusSpeed: number }; floor?: number | null };

async function api<T>(path: string, token?: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API}${path}`, {
    ...init,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...init?.headers },
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error ?? `API error ${response.status}`);
  return body as T;
}

function App() {
  const [session, setSession] = useState<Session | null>(() => {
    const saved = localStorage.getItem('ig-session');
    return saved ? JSON.parse(saved) as Session : null;
  });
  const [me, setMe] = useState<Me | null>(null);
  const [banners, setBanners] = useState<Banner[]>([]);
  const [bannerDetail, setBannerDetail] = useState<BannerDetail | null>(null);
  const [selectedBannerId, setSelectedBannerId] = useState('');
  const [heroCollection, setHeroCollection] = useState<Hero[]>([]);
  const [heroRarityFilter, setHeroRarityFilter] = useState('ALL');
  const [heroClassFilter, setHeroClassFilter] = useState('ALL');
  const [heroStateFilter, setHeroStateFilter] = useState('ALL');
  const [heroSort, setHeroSort] = useState('RARITY');
  const [heroTemplates, setHeroTemplates] = useState<HeroTemplate[]>([]);
  const [featureUnlocks, setFeatureUnlocks] = useState<FeatureUnlock[]>([]);
  const [masterSkills, setMasterSkills] = useState<MasterSkill[]>([]);
  const [playerProfile, setPlayerProfile] = useState<PlayerProfile | null>(null);
  const [profileName, setProfileName] = useState('');
  const [profileAvatarUrl, setProfileAvatarUrl] = useState('');
  const [page, setPage] = useState('overview');
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [loading, setLoading] = useState(false);
  const [rolls, setRolls] = useState<Roll[]>([]);
  const [summonBusy, setSummonBusy] = useState(false);
  const [combatSession, setCombatSession] = useState<CombatSession | null>(null);
  const [dungeonFloors, setDungeonFloors] = useState<DungeonFloorProgress[]>([]);
  const [inventoryItems, setInventoryItems] = useState<InventoryItem[]>([]);
  const [currencyBalances, setCurrencyBalances] = useState<CurrencyBalances | null>(null);
  const [itemCategoryFilter, setItemCategoryFilter] = useState<string>('ALL');
  const [itemSortOrder, setItemSortOrder] = useState<'QUANTITY_DESC' | 'RARITY_DESC' | 'NAME_ASC'>('QUANTITY_DESC');
  const [useTargetHeroId, setUseTargetHeroId] = useState<string>('');
  const [selectedFloor, setSelectedFloor] = useState<number>(1);
  const [floorPreview, setFloorPreview] = useState<{
    floorNumber: number;
    difficultyMultiplier: number;
    rooms: { roomIndex: number; roomType: string; name: string; foes?: { name: string; hp: number; attack: number; element?: string }[] }[];
    floorEvent: { name: string; description: string };
  } | null>(null);
  const [partyHeroIds, setPartyHeroIds] = useState<string[]>([]);
  const [savedPartyHeroIds, setSavedPartyHeroIds] = useState<string[]>([]);
  const [parties, setParties] = useState<Party[]>([]);
  const [selectedPartyId, setSelectedPartyId] = useState('');
  const [partyNameDraft, setPartyNameDraft] = useState('');
  const [equipment, setEquipment] = useState<EquipmentRow[]>([]);
  const [floorDrops, setFloorDrops] = useState<EquipmentRow[]>([]);
  const [equipmentTargetHeroId, setEquipmentTargetHeroId] = useState('');
  const [partySaving, setPartySaving] = useState(false);
  const [developmentBusy, setDevelopmentBusy] = useState('');
  const [now, setNow] = useState(Date.now());
  const [preCombatBuff, setPreCombatBuff] = useState<string>('');

  const displayedHeroes = useMemo(() => heroCollection
    .filter(hero => heroRarityFilter === 'ALL' || hero.rarity === Number(heroRarityFilter))
    .filter(hero => heroClassFilter === 'ALL' || hero.heroClass === heroClassFilter)
    .filter(hero => heroStateFilter === 'ALL' || hero.state === heroStateFilter)
    .slice().sort((a, b) => heroSort === 'LEVEL' ? b.level - a.level || b.rarity - a.rarity
      : heroSort === 'POWER' ? ((b.derivedStats?.attack ?? 0) + (b.derivedStats?.defense ?? 0) + (b.derivedStats?.maxHp ?? 0) + (b.derivedStats?.speed ?? 0)) - ((a.derivedStats?.attack ?? 0) + (a.derivedStats?.defense ?? 0) + (a.derivedStats?.maxHp ?? 0) + (a.derivedStats?.speed ?? 0))
        : b.rarity - a.rarity || a.name.localeCompare(b.name)),
  [heroCollection, heroRarityFilter, heroClassFilter, heroStateFilter, heroSort]);

  const toggleHeroLock = async (hero: Hero) => {
    if (!session) return;
    try {
      const result = await api<{ isLocked: boolean }>(`/api/heroes/${hero.id}/lock`, session.token, { method: 'PATCH', body: JSON.stringify({ isLocked: !hero.isLocked }) });
      setHeroCollection(rows => rows.map(row => row.id === hero.id ? { ...row, isLocked: result.isLocked } : row));
    } catch (e) { setError((e as Error).message); }
  };

  const refresh = useCallback(async (token = session?.token) => {
    if (!token) return;
    const data = await api<Me>('/api/me', token);
    setMe(data);
  }, [session?.token]);

  const developHero = async (hero: Hero, action: 'level-up' | 'promote' | 'awaken') => {
    if (!session) return;
    setDevelopmentBusy(`${hero.id}:${action}`); setError(''); setNotice('');
    try {
      await api(`/api/heroes/${hero.id}/${action}`, session.token, { method: 'POST', body: JSON.stringify({}) });
      const [heroes] = await Promise.all([api<Hero[]>('/api/heroes', session.token), refresh(session.token)]);
      setHeroCollection(heroes);
      setNotice(`${hero.name}: thao tác phát triển đã hoàn tất.`);
    } catch (e) { setError((e as Error).message); }
    finally { setDevelopmentBusy(''); }
  };

  const updateHeroSkill = async (hero: Hero, skill: HeroSkill, action: 'unlock' | 'upgrade' | 'behavior', behaviorMode?: 'AUTO' | 'MANUAL') => {
    if (!session) return;
    setDevelopmentBusy(`${hero.id}:${skill.code}`); setError(''); setNotice('');
    try {
      const path = `/api/heroes/${hero.id}/skills/${skill.code}/${action}`;
      await api(path, session.token, { method: action === 'behavior' ? 'PATCH' : 'POST', body: JSON.stringify(action === 'behavior' ? { behaviorMode } : {}) });
      const [heroes] = await Promise.all([api<Hero[]>('/api/heroes', session.token), refresh(session.token)]);
      setHeroCollection(heroes);
      setNotice(`${hero.name}: kỹ năng ${skill.name} đã được cập nhật.`);
    } catch (e) { setError((e as Error).message); }
    finally { setDevelopmentBusy(''); }
  };

  const developmentConfig = (action: string, rank: number) => me?.heroDevelopmentConfigs?.find(config => config.action === action && config.rank === rank);
  const itemQuantity = (itemId: string) => me?.itemInventory?.find(item => item.itemId === itemId)?.quantity ?? 0;
  const selectedParty = parties.find(party => party.id === selectedPartyId);

  const selectParty = (partyId: string, rows = parties) => {
    const party = rows.find(row => row.id === partyId);
    const ids = party?.members.map(row => row.hero.id) ?? [];
    setSelectedPartyId(party?.id ?? ''); setPartyHeroIds(ids); setSavedPartyHeroIds(ids);
  };

  const refreshProfile = useCallback(async (token = session?.token) => {
    if (!token) return;
    const profile = await api<PlayerProfile>('/api/profile', token);
    setPlayerProfile(profile); setProfileName(profile.display_name); setProfileAvatarUrl(profile.avatar_url ?? '');
  }, [session?.token]);

  const previewFloor = async (floorNum: number) => {
    if (!session) return;
    try {
      const res = await api<{
        floorNumber: number;
        difficultyMultiplier: number;
        rooms: { roomIndex: number; roomType: string; name: string; foes?: { name: string; hp: number; attack: number; element?: string }[] }[];
        floorEvent: { name: string; description: string };
      }>(`/api/dungeon/world-seed/reconstruct/${floorNum}`, session.token);
      setFloorPreview(res);
      setSelectedFloor(floorNum);
    } catch (e) { setError((e as Error).message); }
  };

  const refreshDungeonFloors = useCallback(async (token: string) => {
    try {
      const res = await api<{ floors: DungeonFloorProgress[] }>('/api/dungeon/floors', token);
      setDungeonFloors(res.floors);
    } catch { /* ignored */ }
  }, []);

  const refreshInventory = useCallback(async (token = session?.token) => {
    if (!token) return;
    try {
      const [inv, bal] = await Promise.all([
        api<{ items: InventoryItem[] }>('/api/inventory', token),
        api<CurrencyBalances>('/api/economy/balances', token),
      ]);
      setInventoryItems(inv.items);
      setCurrencyBalances(bal);
    } catch { /* ignored */ }
  }, [session?.token]);

  const useInventoryItem = async (itemId: string, quantity = 1, targetHeroId?: string) => {
    if (!session) return;
    setError('');
    try {
      const result = await api<{ heroName: string; fromLevel: number; toLevel: number }>(`/api/inventory/items/${itemId}/use`, session.token, {
        method: 'POST',
        body: JSON.stringify({ quantity, targetHeroId }),
      });
      await refresh();
      await refreshInventory(session.token);
      setNotice(`Đã dùng ${quantity} sách EXP cho ${result.heroName} (${result.fromLevel} -> ${result.toLevel}).`);
    } catch (e) { setError((e as Error).message); }
  };

  const sellInventoryItem = async (itemId: string, quantity = 1) => {
    if (!session) return;
    setError('');
    try {
      const result = await api<{ quantitySold: number; silverEarned: number }>(`/api/inventory/items/${itemId}/sell`, session.token, {
        method: 'POST',
        body: JSON.stringify({ quantity }),
      });
      await refresh();
      await refreshInventory(session.token);
      setNotice(`Đã bán ${result.quantitySold} vật phẩm, nhận được ${result.silverEarned} Xu Bạc.`);
    } catch (e) { setError((e as Error).message); }
  };

  const refreshEquipment = useCallback(async (token = session?.token) => {
    if (!token) return;
    const [items, drops] = await Promise.all([
      api<EquipmentRow[]>('/api/equipment', token),
      api<EquipmentRow[]>('/api/equipment/floor-drops', token),
    ]);
    setEquipment(items); setFloorDrops(drops);
  }, [session?.token]);

  useEffect(() => {
    if (!session) { setMe(null); return; }
    refresh().catch(() => { localStorage.removeItem('ig-session'); setSession(null); });
    refreshProfile().catch(e => setError((e as Error).message));
  }, [session, refresh, refreshProfile]);

  useEffect(() => {
    if (!session || !me?.master) return;
    api<Banner[]>('/api/gacha/banners', session.token).then(rows => {
      setBanners(rows);
      setSelectedBannerId(current => rows.some(row => row.id === current) ? current : rows[0]?.id ?? '');
    }).catch(e => setError((e as Error).message));
    api<Roll[]>('/api/gacha/history', session.token).then(setRolls).catch(e => setError((e as Error).message));
    api<Hero[]>('/api/heroes', session.token).then(setHeroCollection).catch(e => setError((e as Error).message));
    api<HeroTemplate[]>('/api/hero-templates', session.token).then(setHeroTemplates).catch(e => setError((e as Error).message));
    api<CombatSession | null>('/api/combat/session/active', session.token).then(active => active ?? api<CombatSession | null>('/api/combat/session/latest', session.token)).then(setCombatSession).catch(e => setError((e as Error).message));
    api<Party[]>('/api/parties', session.token).then(rows => { setParties(rows); const selected = rows.find(row => row.isDefault) ?? rows[0]; const ids = selected?.members.map(row => row.hero.id) ?? []; setSelectedPartyId(selected?.id ?? ''); setPartyHeroIds(ids); setSavedPartyHeroIds(ids); }).catch(e => setError((e as Error).message));
    refreshEquipment(session.token).catch(e => setError((e as Error).message));
    refreshDungeonFloors(session.token);
  }, [session, me?.master?.id, refreshEquipment]);

  useEffect(() => {
    if (!session || !me?.master) return;
    api<FeatureUnlock[]>('/api/master/features', session.token).then(setFeatureUnlocks).catch(e => setError((e as Error).message));
    api<MasterSkill[]>('/api/master/skills', session.token).then(setMasterSkills).catch(e => setError((e as Error).message));
  }, [session?.token, me?.master?.level]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, []);

  const cooldown = useMemo(() => {
    const until = combatSession?.cooldownUntil ? Date.parse(combatSession.cooldownUntil) : 0;
    return Math.max(0, Math.ceil((until - now) / 1000));
  }, [now, combatSession?.cooldownUntil]);
  const skillCooldown = useMemo(() => {
    const until = combatSession?.combatState?.masterSkillCooldownUntil ? Date.parse(combatSession.combatState.masterSkillCooldownUntil) : 0;
    return Math.max(0, Math.ceil((until - now) / 1000));
  }, [now, combatSession?.combatState?.masterSkillCooldownUntil]);
  const buff = combatSession?.activeBuffId ?? preCombatBuff;
  const setAuthenticated = (value: Session) => {
    localStorage.setItem('ig-session', JSON.stringify(value));
    setSession(value);
    setError('');
  };

  const doSummon = async (count: 1 | 10) => {
    if (!session || !me?.master || !selectedBannerId) return;
    setSummonBusy(true); setError('');
    try {
      const result = await api<{ results: Roll[] }>('/api/gacha/summon', session.token, {
        method: 'POST', headers: { 'Idempotency-Key': crypto.randomUUID() }, body: JSON.stringify({ bannerId: selectedBannerId, rollCount: count }),
      });
      setRolls(result.results);
      await refresh();
      setHeroCollection(await api<Hero[]>('/api/heroes', session.token));
      setNotice(`Hoàn tất ${count} lượt triệu hồi.`);
    } catch (e) { setError((e as Error).message); }
    finally { setSummonBusy(false); }
  };

  const startCombat = async () => {
    if (!session || !selectedParty?.isDefault || partyHeroIds.length === 0 || JSON.stringify(partyHeroIds) !== JSON.stringify(savedPartyHeroIds)) return;
    setError('');
    try { setCombatSession(await api<CombatSession>('/api/combat/session/start', session.token, { method: 'POST' })); }
    catch (e) { setError((e as Error).message); }
  };

  const switchBuff = async (buffId: string) => {
    if (!session || !combatSession) return;
    setError('');
    try {
      const result = await api<{ session: CombatSession; remainingCooldownSeconds: number }>(`/api/combat/session/${combatSession.id}/buff`, session.token, { method: 'POST', body: JSON.stringify({ buffId }) });
      setCombatSession(result.session);
    } catch (e) { setError((e as Error).message); }
  };

  const saveParty = async () => {
    if (!session || !selectedPartyId) return;
    setPartySaving(true); setError('');
    try {
      const rows = await api<Party[]>(`/api/parties/${selectedPartyId}`, session.token, { method: 'PUT', body: JSON.stringify({ heroIds: partyHeroIds }) });
      setParties(rows); selectParty(selectedPartyId, rows); setNotice('Party saved.');
    } catch (e) { setError((e as Error).message); }
    finally { setPartySaving(false); }
  };

  const createParty = async () => {
    if (!session || !partyNameDraft.trim()) return;
    setError('');
    try {
      const rows = await api<Party[]>('/api/parties', session.token, { method: 'POST', body: JSON.stringify({ name: partyNameDraft }) });
      setParties(rows); setPartyNameDraft('');
      const created = rows.find(party => !parties.some(old => old.id === party.id));
      selectParty(created?.id ?? rows.at(-1)?.id ?? '', rows); setNotice('Party created.');
    } catch (e) { setError((e as Error).message); }
  };

  const renameParty = async () => {
    if (!session || !selectedPartyId || !partyNameDraft.trim()) return;
    try {
      const rows = await api<Party[]>(`/api/parties/${selectedPartyId}`, session.token, { method: 'PUT', body: JSON.stringify({ name: partyNameDraft }) });
      setParties(rows); setPartyNameDraft(''); setNotice('Party renamed.');
    } catch (e) { setError((e as Error).message); }
  };

  const setPartyDefault = async () => {
    if (!session || !selectedPartyId) return;
    try {
      const rows = await api<Party[]>(`/api/parties/${selectedPartyId}/default`, session.token, { method: 'PATCH', body: JSON.stringify({}) });
      setParties(rows); selectParty(selectedPartyId, rows); setNotice('Default party updated.');
    } catch (e) { setError((e as Error).message); }
  };

  const deleteParty = async () => {
    if (!session || !selectedPartyId) return;
    try {
      const rows = await api<Party[]>(`/api/parties/${selectedPartyId}`, session.token, { method: 'DELETE' });
      setParties(rows);
      const next = rows.find(party => party.isDefault) ?? rows[0];
      selectParty(next?.id ?? '', rows); setNotice('Party deleted.');
    } catch (e) { setError((e as Error).message); }
  };

  const togglePartyHero = (heroId: string) => {
    setPartyHeroIds(current => current.includes(heroId) ? current.filter(id => id !== heroId) : current.length < 5 ? [...current, heroId] : current);
  };

  const movePartyHero = (heroId: string, direction: -1 | 1) => {
    setPartyHeroIds(current => {
      const index = current.indexOf(heroId);
      const target = index + direction;
      if (index < 0 || target < 0 || target >= current.length) return current;
      const reordered = [...current];
      [reordered[index], reordered[target]] = [reordered[target], reordered[index]];
      return reordered;
    });
  };

  const changeTargetPriority = async (priority: 'LOWEST_HP' | 'HIGHEST_ATK' | 'FRONTLINE' | 'BALANCED') => {
    if (!session || !combatSession) return;
    setError('');
    try {
      const updated = await api<CombatSession>(`/api/combat/session/${combatSession.id}/target-priority`, session.token, {
        method: 'POST',
        body: JSON.stringify({ priority }),
      });
      setCombatSession(updated);
      setNotice(`Ưu tiên mục tiêu đã chuyển sang: ${priority}`);
    } catch (e) { setError((e as Error).message); }
  };

  const retreatCombat = async () => {
    if (!session || !combatSession) return;
    if (!window.confirm('Bạn có chắc chắn muốn rút lui chiến thuật? Các tướng sống sót sẽ bảo toàn tính mạng nhưng trận đấu tính là Thất bại.')) return;
    setError('');
    try {
      const updated = await api<CombatSession>(`/api/combat/session/${combatSession.id}/retreat`, session.token, { method: 'POST' });
      setCombatSession(updated);
      await refresh();
      setHeroCollection(await api<Hero[]>('/api/heroes', session.token));
      setNotice('Đã rút lui chiến thuật an toàn.');
    } catch (e) { setError((e as Error).message); }
  };

  const useMasterSkill = async (skillCode: string) => {
    if (!session || !combatSession) return;
    setError('');
    try {
      setCombatSession(await api<CombatSession>(`/api/combat/session/${combatSession.id}/skills/${skillCode}/use`, session.token, { method: 'POST' }));
      setNotice('Kỹ năng Master đã kích hoạt.');
    } catch (e) { setError((e as Error).message); }
  };

  const saveProfile = async () => {
    if (!session) return;
    setError('');
    try {
      await api('/api/profile', session.token, { method: 'PATCH', body: JSON.stringify({ display_name: profileName, avatar_url: profileAvatarUrl || null }) });
      await refreshProfile(); setNotice('Hồ sơ đã được cập nhật.');
    } catch (e) { setError((e as Error).message); }
  };

  const saveSettings = async (settings: PlayerProfile['settings']) => {
    if (!session) return;
    setError('');
    try {
      await api('/api/profile', session.token, { method: 'PATCH', body: JSON.stringify({ settings }) });
      await refreshProfile(); setNotice('Cài đặt đã được lưu.');
    } catch (e) { setError((e as Error).message); }
  };

  const logout = async () => {
    if (session) {
      try { await api('/api/auth/logout', session.token, { method: 'POST' }); } catch { /* Session may already be expired or revoked. */ }
    }
    localStorage.removeItem('ig-session'); setSession(null);
  };

  useEffect(() => {
    if (!session || !combatSession || combatSession.status !== 'ACTIVE') return;
    let busy = false;
    const timer = window.setInterval(async () => {
      if (busy) return;
      busy = true;
      try {
        const updated = await api<CombatSession>(`/api/combat/session/${combatSession.id}/advance`, session.token, { method: 'POST' });
        setCombatSession(updated);
        if (updated.status !== 'ACTIVE') {
          await refresh();
          setHeroCollection(await api<Hero[]>('/api/heroes', session.token));
          await refreshEquipment(session.token);
          const savedParties = await api<Party[]>('/api/parties', session.token);
          setParties(savedParties);
          const defaultParty = savedParties.find(party => party.isDefault);
          selectParty(defaultParty?.id ?? '', savedParties);
          setNotice(`Battle ${updated.battleReport?.result ?? updated.status.toLowerCase()}.`);
        }
      } catch (e) { setError((e as Error).message); }
      finally { busy = false; }
    }, 1200);
    return () => window.clearInterval(timer);
  }, [session?.token, combatSession?.id, combatSession?.status, refresh, refreshEquipment]);

  const equipItem = async (itemId: string) => {
    if (!session || !equipmentTargetHeroId) return;
    setError('');
    try {
      await api(`/api/equipment/${itemId}/equip`, session.token, { method: 'PUT', body: JSON.stringify({ heroId: equipmentTargetHeroId }) });
      await refreshEquipment();
      setHeroCollection(await api<Hero[]>('/api/heroes', session.token));
      setNotice('Equipment equipped.');
    } catch (e) { setError((e as Error).message); }
  };

  const unequipItem = async (itemId: string) => {
    if (!session) return;
    setError('');
    try {
      await api(`/api/equipment/${itemId}/unequip`, session.token, { method: 'POST' });
      await refreshEquipment();
      setHeroCollection(await api<Hero[]>('/api/heroes', session.token));
      setNotice('Equipment returned to inventory.');
    } catch (e) { setError((e as Error).message); }
  };

  const pickUpItem = async (itemId: string) => {
    if (!session) return;
    setError('');
    try {
      await api(`/api/equipment/${itemId}/pickup`, session.token, { method: 'POST' });
      await refreshEquipment(); setNotice('Floor drop picked up.');
    } catch (e) { setError((e as Error).message); }
  };

  const exchangeNormalScroll = async () => {
    if (!session || !me?.master) return;
    setLoading(true); setError('');
    try {
      await api('/api/economy/exchange-scrolls', session.token, { method: 'POST', body: JSON.stringify({ amount: 1 }) });
      await refresh();
      setNotice('Đã đổi 10.000 Xu Bạc lấy 1 Thiên Thư thường.');
    } catch (e) { setError((e as Error).message); }
    finally { setLoading(false); }
  };

  const banner = banners.find(item => item.id === selectedBannerId);
  useEffect(() => {
    if (!session || !selectedBannerId) { setBannerDetail(null); return; }
    api<BannerDetail>(`/api/gacha/banners/${selectedBannerId}`, session.token).then(setBannerDetail).catch(() => setBannerDetail(null));
  }, [session?.token, selectedBannerId]);
  const bannerScrollType = banner?.bannerType === 'SPECIAL' ? 'SPECIAL' : banner?.bannerType === 'LIMITED' ? 'LIMITED' : 'NORMAL';
  const scrollCount = me?.summonInventory?.find(item => item.scrollType === bannerScrollType)?.quantity ?? 0;

  if (!session) return <AuthScreen onAuthenticated={setAuthenticated} />;

  const nav = [
    { id: 'overview', icon: '⌂', label: 'Tổng quan' },
    { id: 'profile', icon: '◎', label: 'Hồ sơ' },
    { id: 'summon', icon: '✦', label: 'Thiên Thư' },
    { id: 'heroes', icon: '♙', label: 'Hero' },
    { id: 'battle', icon: '⚔', label: 'Chiến đấu' },
    { id: 'base', icon: '⌂', label: 'Căn cứ' },
    { id: 'survival', icon: '☘', label: 'Sinh tồn' },
    { id: 'medical', icon: '✚', label: 'Y tế' },
    { id: 'admin', icon: '⚙', label: 'Quản trị' },
  ];

  return <div className="app-shell">
    <aside className="sidebar">
      <div className="brand"><span className="brand-mark">∞</span><span>INFINITE<br /><b>GACHA</b></span></div>
      <div className="realm-label">COMMAND HALL</div>
      <nav>{nav.map(item => <button key={item.id} className={`nav-item ${page === item.id ? 'active' : ''}`} onClick={() => { setPage(item.id); setError(''); setNotice(''); }}><span className="nav-icon">{item.icon}</span>{item.label}{item.id === 'summon' && <span className="nav-dot" />}</button>)}</nav>
      <div className="sidebar-bottom"><div className="online-pill"><i /> API prototype</div><button className="account-chip" onClick={() => void logout()}><span className="avatar-small">{session.username.slice(0, 1).toUpperCase()}</span><span><b>{session.username}</b><small>Đăng xuất</small></span><span className="logout">↗</span></button></div>
    </aside>

    <main className="main-area">
      <header className="topbar"><div className="breadcrumb">THẾ GIỚI RIÊNG <span>/</span> <b>{nav.find(n => n.id === page)?.label.toUpperCase()}</b></div><div className="topbar-right"><span className="utc-tag">UTC+7</span><span className="top-divider" /><span className="master-tag"><i className="master-gem">◆</i> {me?.master ? `Master Lv.${me.master.level}` : 'Chưa khởi tạo Master'}</span></div></header>
      <div className="content">
        {error && <div className="toast error-toast"><span>!</span>{error}<button onClick={() => setError('')}>×</button></div>}
        {notice && <div className="toast success-toast"><span>✓</span>{notice}<button onClick={() => setNotice('')}>×</button></div>}

        {page === 'base' && <BasePage token={session.token} onError={setError} onNotice={setNotice} />}
        {page === 'survival' && <SurvivalPage token={session.token} onError={setError} onNotice={setNotice} />}
        {page === 'medical' && <MedicalPage token={session.token} onError={setError} onNotice={setNotice} />}

        {page === 'admin' && <AdminPage onError={setError} onNotice={setNotice} />}

        {page === 'overview' && <>
          <div className="page-heading"><div><div className="eyebrow">PRIVATE WORLD · PHASE 1</div><h1>Trung tâm chỉ huy</h1><p>Chào mừng trở lại, {me?.master?.masterName ?? session.username}. Hành trình của bạn bắt đầu từ đây.</p></div><div className="date-chip"><span className="date-icon">◷</span><span><b>Chu kỳ tuần</b><small>Reset thứ Năm · 00:00 UTC+7</small></span></div></div>
          {!me?.master ? <section className="setup-card"><div className="setup-emblem">✧</div><div className="setup-copy"><div className="eyebrow">BƯỚC ĐẦU TIÊN</div><h2>Khởi tạo Master</h2><p>Mỗi tài khoản gắn với duy nhất một Master. Hãy chọn tên để bắt đầu.</p></div><MasterForm token={session.token} onCreated={async () => { await refresh(); setNotice('Master đã được khởi tạo.'); }} onError={setError} /></section> : <>
            <div className="stat-grid">
              <StatCard icon="◈" label="Cấp Master" value={`Lv. ${me.master.level}`} sub={`EXP dư: ${me.master.exp}`} tone="violet" />
              <StatCard icon="◉" label="Xu Bạc" value={Number(me.master.silverCoins).toLocaleString('vi-VN')} sub="10.000 / Thiên Thư thường" tone="gold" />
              <StatCard icon="✦" label="Ngọc" value={Number(me.master.gems).toLocaleString('vi-VN')} sub="Đơn vị tiền tệ nạp" tone="blue" />
              <StatCard icon="♙" label="Hero sở hữu" value={String(heroCollection.length)} sub="Hero đã lưu trong bộ sưu tập" tone="rose" />
            </div>
            <section className="panel"><div className="panel-head"><div><div className="eyebrow">MASTER PROGRESSION</div><h2>Tính năng đã mở khóa</h2></div></div><div className="template-grid">{featureUnlocks.map(feature => <article className="template-card" key={feature.featureCode}><div className="hero-card-top"><span>{feature.unlocked ? 'ĐÃ MỞ' : 'ĐANG KHÓA'}</span><small>Master Lv.{feature.requiredMasterLevel}</small></div><h3>{feature.featureName}</h3><code>{feature.featureCode}</code></article>)}</div></section>
            <div className="dashboard-grid">
              <section className="panel world-panel"><div className="panel-head"><div><div className="eyebrow">DUNGEON WORLD</div><h2>Thế giới của bạn</h2></div><span className="panel-icon">⌘</span></div>
                {me.world ? <div className="world-created"><div className="world-orb">◉</div><div className="world-info"><b>World đã khởi tạo</b><span>Floor {me.world.currentFloor} · Độ khó ×{me.world.difficultyMultiplier.toFixed(2)}</span><code>SEED {me.world.worldSeed.slice(0, 18).toUpperCase()}…</code></div><span className="status-live">ĐANG HOẠT ĐỘNG</span></div> : <div className="empty-world"><div className="map-art"><span>✧</span><i /><i /><i /><i /></div><h3>Một thế giới đang chờ bạn</h3><p>World Seed được tạo một lần và cố định cho thế giới này.</p><button className="primary-button" disabled={loading} onClick={async () => { setLoading(true); setError(''); try { await api('/api/world/create', session.token, { method: 'POST', body: '{}' }); await refresh(); setNotice('World và Seed đã được tạo.'); } catch (e) { setError((e as Error).message); } finally { setLoading(false); } }}>{loading ? 'Đang tạo…' : 'Khởi tạo World'} <span>→</span></button></div>}
              </section>
              <section className="panel quick-panel"><div className="panel-head"><div><div className="eyebrow">BẮT ĐẦU NHANH</div><h2>Hành động</h2></div></div><button className="quick-action" onClick={() => setPage('summon')}><span className="quick-icon scroll-icon">卷</span><span><b>Triệu hồi Hero</b><small>Thiên Thư · Pity 70</small></span><i>→</i></button><button className="quick-action" onClick={() => setPage('heroes')}><span className="quick-icon hero-icon">♙</span><span><b>Bộ sưu tập Hero</b><small>{heroCollection.length} Hero đang sở hữu</small></span><i>→</i></button><button className="quick-action" onClick={() => setPage('battle')}><span className="quick-icon battle-icon">⚔</span><span><b>Vào chiến đấu</b><small>Auto Battle · PvE</small></span><i>→</i></button><div className="pve-note"><span>◈</span><p><b>PvE trước, PvP sau.</b><br />Thế giới chung sẽ mở ở giai đoạn cuối.</p></div></section>
            </div>
          </>}
        </>}

        {page === 'profile' && playerProfile && <section className="feature-page"><div className="page-heading"><div><div className="eyebrow">PLAYER PROFILE</div><h1>Hồ sơ người chơi</h1><p>Quản lý tên hiển thị, ảnh đại diện và cài đặt.</p></div></div><div className="dashboard-grid"><section className="panel"><div className="panel-head"><div><div className="eyebrow">PROFILE DETAILS</div><h2>Thông tin hiển thị</h2></div></div>{playerProfile.avatar_url && <img src={playerProfile.avatar_url} alt="Avatar" width="80" height="80" referrerPolicy="no-referrer" />}<label>Tên hiển thị<input maxLength={32} value={profileName} onChange={e => setProfileName(e.target.value)} /></label><label>Avatar URL<input maxLength={255} type="url" value={profileAvatarUrl} onChange={e => setProfileAvatarUrl(e.target.value)} placeholder="https://..." /></label><button className="primary-button" onClick={() => void saveProfile()}>Lưu hồ sơ</button></section><section className="panel"><div className="panel-head"><div><div className="eyebrow">PLAYER SETTINGS</div><h2>Cài đặt</h2></div></div><label>Ngôn ngữ<select value={playerProfile.settings.language ?? 'vi'} onChange={e => void saveSettings({ ...playerProfile.settings, language: e.target.value })}><option value="vi">Tiếng Việt</option><option value="en">English</option></select></label><label><input type="checkbox" checked={playerProfile.settings.soundEnabled ?? true} onChange={e => void saveSettings({ ...playerProfile.settings, soundEnabled: e.target.checked })} /> Âm thanh</label><label><input type="checkbox" checked={playerProfile.settings.notificationsEnabled ?? true} onChange={e => void saveSettings({ ...playerProfile.settings, notificationsEnabled: e.target.checked })} /> Thông báo</label></section></div><section className="panel"><div className="panel-head"><div><div className="eyebrow">PLAYER PROGRESS</div><h2>Tiến trình tổng thể</h2></div></div><div className="stat-grid"><StatCard icon="◈" label="Master" value={`Lv. ${playerProfile.progress_summary.master_level}`} sub="Cấp hiện tại" tone="violet" /><StatCard icon="⌂" label="Tầng cao nhất" value={String(playerProfile.progress_summary.world_floor)} sub="World hiện tại" tone="gold" /><StatCard icon="♙" label="Hero hoạt động" value={String(playerProfile.progress_summary.active_heroes)} sub={`${playerProfile.progress_summary.heroes_owned} sở hữu`} tone="rose" /><StatCard icon="✦" label="Triệu hồi" value={String(playerProfile.progress_summary.summons_made)} sub="Lượt đã lưu" tone="blue" /></div></section></section>}

        {page === 'summon' && <section className="feature-page"><div className="page-heading"><div><div className="eyebrow">GACHA · SUMMON</div><h1>Điện Thiên Thư</h1><p>Triệu hồi đồng hành cho chuyến hành trình của Master.</p></div><div className="currency-chip">◉ <b>{Number(me?.master?.silverCoins ?? 0).toLocaleString('vi-VN')}</b><small>Xu Bạc</small></div></div>
          <div className="banner-card"><div className="banner-glow" /><div className="banner-content"><div className="limited-tag"><span />{banner ? `${banner.bannerType} BANNER` : 'CHƯA CÓ BANNER'}</div><h2>{banner?.name ?? 'Banner chưa được cấu hình'}<br /><em>{banner ? 'Khế ước Thiên Thư' : 'Đang chờ cấu hình pool'}</em></h2><p>{banner ? `Pool và pity được lưu cho banner này. Thiên Thư ${bannerScrollType === 'NORMAL' ? 'thường' : bannerScrollType === 'LIMITED' ? 'giới hạn' : 'đặc biệt'} sẽ bị trừ khi triệu hồi.` : 'Hãy cấu hình banner, pool Hero và nguyên liệu trước khi mở triệu hồi.'}</p><div className="banner-bottom"><span>✦ PITY <b>70</b></span><span>◈ TỶ LỆ CƠ BẢN <b>0,4%</b></span></div></div><div className="banner-character"><div className="character-halo">✧</div><div className="character-silhouette">♙</div><div className="star-row">✦ ✦ ✦ ✦ ✦</div></div></div>
          {bannerDetail && <div className="template-section"><div className="panel-head"><div><div className="eyebrow">BANNER DETAILS</div><h2>{bannerDetail.banner.name} · Hero Pool</h2></div><span className="template-note">Pity {bannerDetail.pity.currentCount}/{bannerDetail.pity.hardPityAt}</span></div><div className="banner-bottom"><span>5★ next roll <b>{bannerDetail.rates.fiveStarHeroPercent.toFixed(2)}%</b></span><span>Other Heroes <b>{bannerDetail.rates.otherHeroPercent.toFixed(2)}%</b></span><span>Materials <b>{bannerDetail.rates.materialPercent.toFixed(2)}%</b></span></div><div className="template-grid">{bannerDetail.pool.map(item => <article className="template-card" key={`${item.poolGroup}-${item.rewardId}`}><div className="hero-card-top"><span>{item.rarity ? `${item.rarity}★` : item.rewardType}</span><small>{item.poolGroup}</small></div><h3>{item.rewardName}</h3><code>{item.rewardId}</code></article>)}</div></div>}
{banners.length > 0 && <div className="banner-picker"><label htmlFor="banner-choice">Banner đang mở</label><select id="banner-choice" value={selectedBannerId} onChange={e => setSelectedBannerId(e.target.value)}>{banners.map(item => <option key={item.id} value={item.id}>{item.name} · {item.bannerType}</option>)}</select><span>Thiên Thư trong kho: <b>{scrollCount}</b></span></div>}
          <div className="exchange-card"><div className="exchange-scroll"><span className="scroll-seal">卷</span><span><b>Thiên Thư thường</b><small>Trong kho: {me?.summonInventory?.find(i => i.scrollType === 'NORMAL')?.quantity ?? 0}</small></span></div><div className="exchange-details"><span>{me?.weeklyScrollExchange?.quantity ?? 0} / 50 vé tuần này</span><button className="secondary-button" disabled={loading || !me?.master || (me?.weeklyScrollExchange?.quantity ?? 0) >= 50 || Number(me?.master?.silverCoins ?? 0) < 10000} onClick={() => void exchangeNormalScroll()}>{loading ? 'Đang đổi…' : 'Đổi 1 vé · 10.000 Xu'}</button></div></div>
          <div className="summon-controls"><div><h3>{bannerScrollType === 'NORMAL' ? 'Thiên Thư thường' : bannerScrollType === 'LIMITED' ? 'Thiên Thư giới hạn' : 'Thiên Thư đặc biệt'} <span className="white-scroll">卷</span></h3><p>1 vé / lượt · 10 vé / 10 lượt. Mỗi banner có bộ đếm pity độc lập.</p><p className="prototype-warning">Hero trùng chuyển thành 1 Thiên Mệnh cộng vào chính Hero đó. Kết quả được lưu cùng lịch sử triệu hồi.</p></div><div className="summon-buttons"><button className="secondary-button" disabled={summonBusy || !banner || scrollCount < 1} onClick={() => void doSummon(1)}>Triệu hồi ×1</button><button className="primary-button" disabled={summonBusy || !banner || scrollCount < 10} onClick={() => void doSummon(10)}>Triệu hồi ×10</button></div></div>
          {rolls.length > 0 && <div className="results-panel"><div className="panel-head"><div><div className="eyebrow">KẾT QUẢ TRIỆU HỒI</div><h2>{rolls.length} vật phẩm nhận được</h2></div><button className="text-button" onClick={() => setRolls([])}>Xóa kết quả</button></div><div className="result-grid">{rolls.map((r, i) => <div className={`result-card rarity-${r.rarity}`} key={`${r.rollNumber}-${i}`}><span className="result-rarity">{'✦'.repeat(Math.min(r.rarity, 5))}</span><span className="result-art">{r.itemType === 'HERO' ? '♙' : '◈'}</span><b>{r.rewardName}</b><small>{r.itemType === 'HERO' ? 'Hero' : 'Tài nguyên'}{r.isDuplicate ? ' · Trùng' : ''}</small></div>)}</div></div>}
        </section>}

        {page === 'inventory' && <section className="feature-page">
          <div className="page-heading">
            <div>
              <div className="eyebrow">INVENTORY &amp; ECONOMY</div>
              <h1>Túi đồ &amp; Tài nguyên</h1>
              <p>Quản lý vật phẩm phát triển, trang bị, và giao dịch tài nguyên.</p>
            </div>
            <div className="currency-chip">
              ◉ <b>{currencyBalances?.silverCoins ? Number(currencyBalances.silverCoins).toLocaleString('vi-VN') : Number(me?.master?.silverCoins ?? 0).toLocaleString('vi-VN')}</b>
              <small>Xu Bạc</small>
            </div>
          </div>

          <div className="panel" style={{ display: 'flex', gap: '1.5rem', flexWrap: 'wrap', alignItems: 'center' }}>
            <div>
              <small style={{ color: 'var(--text-muted)' }}>VÉ THIÊN THƯ THƯỜNG</small>
              <div style={{ fontSize: '1.2rem', fontWeight: 'bold', color: '#ffb' }}>
                {currencyBalances?.summonTickets.normal ?? (me?.summonInventory?.find(i => i.scrollType === 'NORMAL')?.quantity ?? 0)} vé
              </div>
            </div>
            <div>
              <small style={{ color: 'var(--text-muted)' }}>VÉ ĐẶC BIỆT</small>
              <div style={{ fontSize: '1.2rem', fontWeight: 'bold', color: '#f99' }}>
                {currencyBalances?.summonTickets.special ?? (me?.summonInventory?.find(i => i.scrollType === 'SPECIAL')?.quantity ?? 0)} vé
              </div>
            </div>
            <div>
              <small style={{ color: 'var(--text-muted)' }}>ĐỔI VÉ TUẦN (10.000 BẠC/VÉ)</small>
              <div style={{ fontSize: '1.2rem', fontWeight: 'bold', color: '#6cf' }}>
                {currencyBalances?.weeklyExchange.exchanged ?? (me?.weeklyScrollExchange?.quantity ?? 0)} / {currencyBalances?.weeklyExchange.weeklyCap ?? 50}
              </div>
            </div>
          </div>

          <div className="template-section">
            <div className="panel-head">
              <div>
                <div className="eyebrow">ITEMS INVENTORY</div>
                <h2>Kho vật phẩm</h2>
              </div>
              <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center' }}>
                <select
                  value={itemCategoryFilter}
                  onChange={e => setItemCategoryFilter(e.target.value)}
                  style={{ padding: '0.2rem 0.5rem', fontSize: '0.8rem' }}
                >
                  <option value="ALL">Tất cả danh mục</option>
                  <option value="DEVELOPMENT">Phát triển Hero</option>
                  <option value="MATERIAL">Nguyên liệu &amp; Rác</option>
                </select>
                <select
                  value={itemSortOrder}
                  onChange={e => setItemSortOrder(e.target.value as any)}
                  style={{ padding: '0.2rem 0.5rem', fontSize: '0.8rem' }}
                >
                  <option value="QUANTITY_DESC">Số lượng giảm dần</option>
                  <option value="RARITY_DESC">Độ hiếm giảm dần</option>
                  <option value="NAME_ASC">Tên A-Z</option>
                </select>
              </div>
            </div>

            <div className="hero-grid">
              {inventoryItems
                .filter(item => itemCategoryFilter === 'ALL' || item.category === itemCategoryFilter)
                .sort((a, b) => {
                  if (itemSortOrder === 'QUANTITY_DESC') return b.quantity - a.quantity;
                  if (itemSortOrder === 'RARITY_DESC') return b.rarity - a.rarity;
                  return a.name.localeCompare(b.name);
                })
                .map(item => (
                  <article className="template-card" key={item.id}>
                    <div className="hero-card-top">
                      <span>{'★'.repeat(item.rarity)}</span>
                      <small>{item.category}</small>
                    </div>
                    <h3>{item.name}</h3>
                    <p>{item.description}</p>
                    <p><b>Số lượng: {item.quantity}</b> · Giá bán: {item.sellPrice} Bạc</p>

                    <div style={{ display: 'flex', gap: '0.4rem', marginTop: '0.5rem', flexWrap: 'wrap' }}>
                      {item.canUse && (
                        <div style={{ display: 'flex', gap: '0.3rem', width: '100%' }}>
                          <select
                            style={{ flex: 1, fontSize: '0.75rem', padding: '0.2rem' }}
                            value={useTargetHeroId || (heroCollection.find(h => h.state !== 'DEAD' && h.state !== 'DISABLED')?.id ?? '')}
                            onChange={e => setUseTargetHeroId(e.target.value)}
                          >
                            {heroCollection.filter(h => h.state !== 'DEAD' && h.state !== 'DISABLED').map(h => (
                              <option key={h.id} value={h.id}>{h.name} (Lv.{h.level})</option>
                            ))}
                          </select>
                          <button
                            className="primary-button"
                            style={{ padding: '0.2rem 0.5rem', fontSize: '0.75rem' }}
                            onClick={() => void useInventoryItem(item.itemId, 1, useTargetHeroId || (heroCollection.find(h => h.state !== 'DEAD' && h.state !== 'DISABLED')?.id ?? ''))}
                          >
                            Dùng 1
                          </button>
                        </div>
                      )}
                      <button
                        className="secondary-button"
                        style={{ padding: '0.2rem 0.6rem', fontSize: '0.75rem', borderColor: '#ff9900', color: '#ffbb44' }}
                        onClick={() => void sellInventoryItem(item.itemId, 1)}
                      >
                        Bán 1 (+{item.sellPrice} Bạc)
                      </button>
                      {item.quantity >= 5 && (
                        <button
                          className="secondary-button"
                          style={{ padding: '0.2rem 0.6rem', fontSize: '0.75rem', borderColor: '#ff9900', color: '#ffbb44' }}
                          onClick={() => void sellInventoryItem(item.itemId, 5)}
                        >
                          Bán 5 (+{item.sellPrice * 5} Bạc)
                        </button>
                      )}
                    </div>
                  </article>
                ))}
            </div>

            {inventoryItems.length === 0 && (
              <div className="empty-state compact-empty">
                <h2>Túi đồ trống</h2>
                <p>Khám phá Dungeon hoặc triệu hồi gacha để thu thập vật phẩm.</p>
              </div>
            )}
          </div>

          <div className="template-section">
            <div className="panel-head">
              <div>
                <div className="eyebrow">EQUIPMENT INVENTORY</div>
                <h2>Kho trang bị đã sở hữu</h2>
              </div>
            </div>
            <div className="template-grid">
              {equipment.filter(row => row.equipment.location !== 'FLOOR_DROP').map(row => (
                <article className="template-card" key={row.equipment.id}>
                  <div className="hero-card-top">
                    <span>{row.template.rarity}-star</span>
                    <small>{row.template.slotType}</small>
                  </div>
                  <h3>{row.template.name}</h3>
                  <p>HP +{row.template.bonusHp} | ATK +{row.template.bonusAttack}</p>
                  <p>DEF +{row.template.bonusDefense} | SPD +{row.template.bonusSpeed}</p>
                  {row.equipment.location === 'EQUIPPED' ? (
                    <>
                      <small>Trang bị bởi: {heroCollection.find(hero => hero.id === row.equipment.equippedHeroId)?.name ?? 'Hero'}</small>
                      <button className="secondary-button" onClick={() => void unequipItem(row.equipment.id)}>Tháo đồ</button>
                    </>
                  ) : (
                    <div className="summon-buttons">
                      <select
                        aria-label="Choose Hero"
                        value={equipmentTargetHeroId || heroCollection.find(hero => hero.state !== 'DEAD' && hero.state !== 'DISABLED')?.id || ''}
                        onChange={e => setEquipmentTargetHeroId(e.target.value)}
                      >
                        {heroCollection.filter(hero => hero.state !== 'DEAD' && hero.state !== 'DISABLED').map(hero => (
                          <option key={hero.id} value={hero.id}>{hero.name}</option>
                        ))}
                      </select>
                      <button
                        className="secondary-button"
                        disabled={!heroCollection.some(hero => hero.state !== 'DEAD' && hero.state !== 'DISABLED')}
                        onClick={() => void equipItem(row.equipment.id)}
                      >
                        Mặc đồ
                      </button>
                    </div>
                  )}
                </article>
              ))}
            </div>
          </div>

          <div className="template-section">
            <div className="panel-head">
              <div>
                <div className="eyebrow">WORLD FLOOR DROPS</div>
                <h2>Trang bị rơi trên sàn</h2>
              </div>
              <span className="template-note">Rơi từ Hero thường tử trận</span>
            </div>
            <div className="template-grid">
              {floorDrops.map(row => (
                <article className="template-card" key={row.equipment.id}>
                  <div className="hero-card-top">
                    <span>FLOOR {row.equipment.dropFloor ?? row.floor ?? '?'}</span>
                    <small>{row.template.slotType}</small>
                  </div>
                  <h3>{row.template.name}</h3>
                  <p>HP +{row.template.bonusHp} | ATK +{row.template.bonusAttack}</p>
                  <p>DEF +{row.template.bonusDefense} | SPD +{row.template.bonusSpeed}</p>
                  <button className="primary-button" onClick={() => void pickUpItem(row.equipment.id)}>Nhặt đồ</button>
                </article>
              ))}
            </div>
            {floorDrops.length === 0 && (
              <div className="empty-state compact-empty">
                <h2>Không có trang bị rơi trên sàn</h2>
                <p>Trang bị rơi khi Hero thường tử trận sẽ xuất hiện ở đây.</p>
              </div>
            )}
          </div>
        </section>}

        {page === 'heroes' && <section className="feature-page"><div className="page-heading"><div><div className="eyebrow">COLLECTION · HERO</div><h1>Đồng hành</h1><p>{heroCollection.length} Hero đã lưu trong bộ sưu tập.</p></div><button className="secondary-button" onClick={() => setPage('summon')}>✦ Triệu hồi thêm</button></div><div className="panel hero-filters"><label>Độ hiếm<select value={heroRarityFilter} onChange={e => setHeroRarityFilter(e.target.value)}><option value="ALL">Tất cả</option>{[5,4,3,2,1].map(value => <option key={value} value={value}>{value} sao</option>)}</select></label><label>Class<select value={heroClassFilter} onChange={e => setHeroClassFilter(e.target.value)}><option value="ALL">Tất cả</option>{[...new Set(heroCollection.map(hero => hero.heroClass).filter(Boolean))].map(value => <option key={value} value={value}>{value}</option>)}</select></label><label>Trạng thái<select value={heroStateFilter} onChange={e => setHeroStateFilter(e.target.value)}><option value="ALL">Tất cả</option>{[...new Set(heroCollection.map(hero => hero.state))].map(value => <option key={value} value={value}>{value}</option>)}</select></label><label>Sắp xếp<select value={heroSort} onChange={e => setHeroSort(e.target.value)}><option value="RARITY">Độ hiếm</option><option value="LEVEL">Cấp độ</option><option value="POWER">Sức mạnh</option></select></label></div><div className="panel"><b>Vật liệu mẫu</b><p>EXP +100: {me?.itemInventory?.find(item => item.itemId === 'SAMPLE_HERO_EXP_100')?.quantity ?? 0} · Ấn thăng bậc: {me?.itemInventory?.find(item => item.itemId === 'SAMPLE_HERO_PROMOTION_SEAL')?.quantity ?? 0} · Lõi thức tỉnh: {me?.itemInventory?.find(item => item.itemId === 'SAMPLE_HERO_AWAKENING_CORE')?.quantity ?? 0}</p></div>{displayedHeroes.length ? <div className="hero-grid">{displayedHeroes.map(hero => <div className={`hero-card rarity-${hero.rarity}`} key={hero.id}><div className="hero-card-top"><span>{'✦'.repeat(Math.min(hero.rarity, 5))}</span><small>{hero.category}{hero.isLocked ? ' · ĐÃ KHÓA' : ''}</small></div><div className="hero-portrait">♙</div><h3>{hero.name}</h3><p>{hero.rarity}★ · Lv.{hero.level}/{hero.maxLevel ?? 20} · {hero.state}</p><p>EXP {hero.exp ?? '0'}{hero.nextLevelExp ? ` / ${hero.nextLevelExp}` : ' · Chưa đủ dữ liệu cấp tiếp theo'}</p>{hero.derivedStats && <p>HP {hero.derivedStats.hp}/{hero.derivedStats.maxHp} | ATK {hero.derivedStats.attack} | DEF {hero.derivedStats.defense} | SPD {hero.derivedStats.speed}</p>}<p className="hero-resource">Thiên Mệnh: {hero.thienMenh} · Thăng bậc {hero.promotionRank ?? 0} · Thức tỉnh {hero.awakeningRank ?? 0}</p><details className="hero-skills"><summary>Kỹ năng ({hero.skills?.length ?? 0})</summary>{hero.skills?.map(skill => <article className="hero-skill-row" key={skill.code}><b>{skill.name} · Lv.{skill.skillLevel}/{skill.maxLevel}</b><p>{skill.description}</p><small>{skill.effectType} · {skill.skillEffectValue} · Hồi chiêu {skill.cooldownSeconds}s · Mở ở Lv.{skill.unlockLevel}</small>{skill.isUnlocked ? <><label>Hành vi<select value={skill.behaviorMode} disabled={Boolean(developmentBusy) || hero.isLocked} onChange={e => void updateHeroSkill(hero, skill, 'behavior', e.target.value as 'AUTO' | 'MANUAL')}><option value="AUTO">Tự động</option><option value="MANUAL">Thủ công</option></select></label><button className="secondary-button" disabled={Boolean(developmentBusy) || hero.isLocked || skill.skillLevel >= skill.maxLevel || itemQuantity('SAMPLE_HERO_SKILL_BOOK') < 1} onClick={() => void updateHeroSkill(hero, skill, 'upgrade')}>Nâng kỹ năng · 1 sách</button></> : <button className="secondary-button" disabled={Boolean(developmentBusy) || hero.isLocked || !skill.canUnlock} onClick={() => void updateHeroSkill(hero, skill, 'unlock')}>{skill.canUnlock ? 'Mở khóa kỹ năng' : `Mở khóa ở Lv.${skill.unlockLevel}`}</button>}</article>)}</details><button className="secondary-button" onClick={() => void toggleHeroLock(hero)}>{hero.isLocked ? 'Mở khóa Hero' : 'Khóa Hero'}</button><button className="secondary-button" disabled={Boolean(developmentBusy) || itemQuantity('SAMPLE_HERO_EXP_100') < 1 || hero.level >= (hero.maxLevel ?? 20) || hero.state === 'DEAD' || hero.state === 'DISABLED'} onClick={() => void developHero(hero, 'level-up')}>Tăng cấp · +100 EXP</button>{(() => { const config = developmentConfig('PROMOTION', (hero.promotionRank ?? 0) + 1); return <button className="secondary-button" disabled={Boolean(developmentBusy) || !config || itemQuantity(config?.materialItemId ?? '') < (config?.materialQuantity ?? 1) || hero.level < (config?.requiredHeroLevel ?? Infinity) || (hero.promotionRank ?? 0) < (config?.requiredPromotionRank ?? Infinity) || hero.state === 'DEAD' || hero.state === 'DISABLED'} onClick={() => void developHero(hero, 'promote')}>Thăng bậc · {config ? `tốn ${config.materialQuantity} vật liệu` : 'đã đạt giới hạn'}</button>; })()}{(() => { const config = developmentConfig('AWAKENING', (hero.awakeningRank ?? 0) + 1); return <button className="secondary-button" disabled={Boolean(developmentBusy) || !config || itemQuantity(config?.materialItemId ?? '') < (config?.materialQuantity ?? 1) || hero.level < (config?.requiredHeroLevel ?? Infinity) || (hero.promotionRank ?? 0) < (config?.requiredPromotionRank ?? Infinity) || hero.state === 'DEAD' || hero.state === 'DISABLED'} onClick={() => void developHero(hero, 'awaken')}>Thức tỉnh · {config ? `tốn ${config.materialQuantity} vật liệu` : 'đã đạt giới hạn'}</button>; })()}</div>)}</div> : <div className="empty-state compact-empty"><div className="empty-symbol">♙</div><h2>{heroCollection.length ? 'Không có Hero phù hợp' : 'Chưa sở hữu Hero'}</h2><p>{heroCollection.length ? 'Thay đổi bộ lọc để xem Hero.' : 'Hãy triệu hồi để xây dựng bộ sưu tập của bạn.'}</p></div>}<div className="template-section"><div className="panel-head"><div><div className="eyebrow">HERO CONFIGURATION</div><h2>Cấu hình mẫu · 1–5 sao</h2></div><span className="template-note">Chỉ số mẫu ban đầu</span></div><div className="template-grid">{heroTemplates.map(hero => <article className={`template-card rarity-${hero.defaultRarity}`} key={hero.id}><div className="hero-card-top"><span>{'✦'.repeat(hero.defaultRarity)}</span><small>{hero.element}</small></div><h3>{hero.name}</h3><p>{hero.heroClass} · {hero.defaultRarity}★</p><code>{hero.code}</code><div className="template-stats"><span>HP <b>{hero.baseHp}</b></span><span>ATK <b>{hero.baseAttack}</b></span><span>DEF <b>{hero.baseDefense}</b></span><span>SPD <b>{hero.baseSpeed}</b></span></div><small className="sample-tag">MẪU · CHƯA CÂN BẰNG</small></article>)}</div></div></section>}

        {page === 'equipment' && <section className="feature-page"><div className="page-heading"><div><div className="eyebrow">INVENTORY ? EQUIPMENT</div><h1>Equipment</h1><p>Equip items, replace same-slot gear, and recover items dropped by fallen Normal Heroes.</p></div></div>
          <div className="template-section"><div className="panel-head"><div><div className="eyebrow">EQUIPMENT INVENTORY</div><h2>Owned items</h2></div><span className="template-note">Sample stats</span></div><div className="template-grid">{equipment.filter(row => row.equipment.location !== 'FLOOR_DROP').map(row => <article className="template-card" key={row.equipment.id}><div className="hero-card-top"><span>{row.template.rarity}-star</span><small>{row.template.slotType}</small></div><h3>{row.template.name}</h3><p>HP +{row.template.bonusHp} | ATK +{row.template.bonusAttack}</p><p>DEF +{row.template.bonusDefense} | SPD +{row.template.bonusSpeed}</p>{row.equipment.location === 'EQUIPPED' ? <><small>Equipped by {heroCollection.find(hero => hero.id === row.equipment.equippedHeroId)?.name ?? 'Hero'}</small><button className="secondary-button" onClick={() => void unequipItem(row.equipment.id)}>Unequip</button></> : <div className="summon-buttons"><select aria-label="Choose Hero" value={equipmentTargetHeroId || heroCollection.find(hero => hero.state !== 'DEAD' && hero.state !== 'DISABLED')?.id || ''} onChange={e => setEquipmentTargetHeroId(e.target.value)}>{heroCollection.filter(hero => hero.state !== 'DEAD' && hero.state !== 'DISABLED').map(hero => <option key={hero.id} value={hero.id}>{hero.name}</option>)}</select><button className="secondary-button" disabled={!heroCollection.some(hero => hero.state !== 'DEAD' && hero.state !== 'DISABLED')} onClick={() => void equipItem(row.equipment.id)}>Equip</button></div>}</article>)}</div>{equipment.filter(row => row.equipment.location !== 'FLOOR_DROP').length === 0 && <div className="empty-state compact-empty"><h2>No equipment in inventory</h2><p>Apply the sample equipment seed after creating a Master.</p></div>}</div>
          <div className="template-section"><div className="panel-head"><div><div className="eyebrow">WORLD FLOOR DROPS</div><h2>Items to pick up</h2></div><span className="template-note">Must be collected</span></div><div className="template-grid">{floorDrops.map(row => <article className="template-card" key={row.equipment.id}><div className="hero-card-top"><span>FLOOR {row.equipment.dropFloor ?? row.floor ?? '?'}</span><small>{row.template.slotType}</small></div><h3>{row.template.name}</h3><p>HP +{row.template.bonusHp} | ATK +{row.template.bonusAttack}</p><p>DEF +{row.template.bonusDefense} | SPD +{row.template.bonusSpeed}</p><button className="primary-button" onClick={() => void pickUpItem(row.equipment.id)}>Pick up</button></article>)}</div>{floorDrops.length === 0 && <div className="empty-state compact-empty"><h2>No floor drops</h2><p>Items dropped by Normal Hero deaths will appear here.</p></div>}</div>
        </section>}

        {page === 'battle' && <section className="feature-page"><div className="page-heading"><div><div className="eyebrow">PVE ? TACTICAL COMMAND</div><h1>Battlefield</h1><p>Choose a party, then watch the server resolve each turn automatically.</p></div><div className="cooldown-chip">{combatSession?.status === 'ACTIVE' ? (cooldown ? `BUFF COOLDOWN ${cooldown}s` : 'BUFF READY') : 'PVE PROTOTYPE'}</div></div>
          <div className="template-section">
            <div className="panel-head">
              <div>
                <div className="eyebrow">DUNGEON &amp; WORLD SEED PROGRESSION</div>
                <h2>Tiến trình tầng &amp; Tái tạo Seed</h2>
              </div>
              <span className="template-note">
                Seed: {me?.world?.worldSeed ? me.world.worldSeed.slice(0, 8) + '...' : ''} · v{me?.world?.seedAlgorithmVersion ?? 1} · Khó x{me?.world?.difficultyMultiplier.toFixed(2)}
              </span>
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '0.6rem', margin: '0.6rem 0' }}>
              {dungeonFloors.map(f => (
                <div
                  key={f.id}
                  onClick={() => void previewFloor(f.floorNumber)}
                  style={{
                    padding: '0.6rem',
                    background: selectedFloor === f.floorNumber ? 'rgba(100, 200, 255, 0.12)' : 'rgba(255,255,255,0.03)',
                    border: selectedFloor === f.floorNumber ? '1px solid var(--accent, #6cf)' : '1px solid rgba(255,255,255,0.08)',
                    borderRadius: '6px',
                    cursor: 'pointer',
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <b>Tầng {f.floorNumber}</b>
                    <small style={{
                      padding: '0.1rem 0.4rem',
                      borderRadius: '3px',
                      fontSize: '0.7rem',
                      background: f.status === 'CLEARED' ? '#1b4d2e' : f.status === 'CURRENT' ? '#1a365d' : f.status === 'UNLOCKED' ? '#5c4308' : '#333',
                      color: f.status === 'CLEARED' ? '#68d391' : f.status === 'CURRENT' ? '#63b3ed' : f.status === 'UNLOCKED' ? '#f6e05e' : '#aaa',
                    }}>
                      {f.status === 'CLEARED' ? 'Đã vượt' : f.status === 'CURRENT' ? 'Hiện tại' : f.status === 'UNLOCKED' ? 'Đã mở' : 'Khóa'}
                    </small>
                  </div>
                  <p style={{ margin: '0.3rem 0 0.1rem', fontSize: '0.8rem' }}>{f.name}</p>
                  <small style={{ color: 'var(--text-muted)' }}>Độ khó: {f.recommendedPower} lực</small>
                  <div style={{ marginTop: '0.3rem', fontSize: '0.75rem', color: '#ffb' }}>
                    Thưởng: {f.baseRewards.silver} Bạc · {f.baseRewards.masterExp} EXP
                  </div>
                  {f.isFirstClearAvailable && (f.firstClearRewards.normalScrolls || f.firstClearRewards.silver) ? (
                    <div style={{ fontSize: '0.7rem', color: '#f99' }}>
                      Thưởng đầu: {f.firstClearRewards.silver ? '+' + f.firstClearRewards.silver + ' Bạc ' : ''}{f.firstClearRewards.normalScrolls ? '+' + f.firstClearRewards.normalScrolls + ' Vé' : ''}
                    </div>
                  ) : null}
                </div>
              ))}
            </div>

            {floorPreview && (
              <div className="panel" style={{ marginTop: '0.8rem', background: 'rgba(0,0,0,0.25)' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <b>Cấu trúc Tái Tạo Seed: Tầng {floorPreview.floorNumber} (Độ khó x{floorPreview.difficultyMultiplier.toFixed(2)})</b>
                  <button className="secondary-button" style={{ padding: '0.2rem 0.5rem', fontSize: '0.75rem' }} onClick={() => setFloorPreview(null)}>Đóng</button>
                </div>
                <p style={{ margin: '0.4rem 0', fontSize: '0.85rem', color: '#a0aec0' }}>
                  Sự kiện môi trường: <b>{floorPreview.floorEvent.name}</b> — {floorPreview.floorEvent.description}
                </p>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '0.5rem', marginTop: '0.4rem' }}>
                  {floorPreview.rooms.map(r => (
                    <div key={r.roomIndex} style={{ padding: '0.4rem 0.6rem', background: 'rgba(255,255,255,0.04)', borderRadius: '4px' }}>
                      <span style={{ fontSize: '0.75rem', color: r.roomType === 'BOSS' ? '#ff6b6b' : r.roomType === 'REST' ? '#48bb78' : '#eed' }}>
                        [{r.roomType}]
                      </span> <b>{r.name}</b>
                      {r.foes && r.foes.length > 0 && (
                        <div style={{ fontSize: '0.75rem', marginTop: '0.2rem', color: 'var(--text-muted)' }}>
                          Quái vật: {r.foes.map(f => f.name + ' (HP ' + f.hp + ', ATK ' + f.attack + ')').join(', ')}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>

          <div className="battle-scene"><div className="battle-moon">PVE</div><div className="battle-copy"><span className="limited-tag"><span /> DUNGEON ? FLOOR {me?.world?.currentFloor ?? 1}</span><h2>Quiet Forest</h2><p>{me?.world ? `World Seed ${me.world.worldSeed.slice(0, 12)}? ? Difficulty ?${me.world.difficultyMultiplier.toFixed(2)}` : 'Create a World from Overview first.'}</p><div className="battle-squad">{partyHeroIds.map((id, i) => <span key={id} className="occupied">{i + 1}</span>)}{Array.from({ length: Math.max(0, 5 - partyHeroIds.length) }, (_, i) => <span key={`empty-${i}`}>+</span>)}</div></div><div className="battle-stat"><small>STATUS</small><b>{combatSession?.status ?? 'READY'}</b><small>{combatSession?.combatState ? `ROUND ${Math.max(1, combatSession.combatState.round - 1)}` : `${partyHeroIds.length} / 5 HEROES`}</small></div></div>
          <div className="panel party-manager"><label>Party<select value={selectedPartyId} onChange={e => selectParty(e.target.value)}>{parties.map(party => <option key={party.id} value={party.id}>{party.name}{party.isDefault ? ' · Mặc định' : ''}</option>)}</select></label><input maxLength={60} value={partyNameDraft} onChange={e => setPartyNameDraft(e.target.value)} placeholder="Tên đội mới" /><button className="secondary-button" disabled={!partyNameDraft.trim() || combatSession?.status === 'ACTIVE'} onClick={() => void createParty()}>Tạo đội</button><button className="secondary-button" disabled={!selectedParty || !partyNameDraft.trim() || combatSession?.status === 'ACTIVE'} onClick={() => void renameParty()}>Đổi tên</button><button className="secondary-button" disabled={!selectedParty || selectedParty.isDefault || combatSession?.status === 'ACTIVE'} onClick={() => void setPartyDefault()}>Đặt mặc định</button><button className="secondary-button" disabled={!selectedParty || combatSession?.status === 'ACTIVE'} onClick={() => void deleteParty()}>Xóa đội</button><span>{selectedParty?.members.length ?? 0}/5 Hero · {selectedParty?.isDefault ? 'Đội dùng cho PvE' : 'Chưa phải đội PvE mặc định'}</span></div><div className="template-section"><div className="panel-head"><div><div className="eyebrow">COMBAT PARTY</div><h2>Select up to 5 active Heroes</h2></div><button className="secondary-button" disabled={partySaving || combatSession?.status === 'ACTIVE'} onClick={() => void saveParty()}>{partySaving ? 'Saving?' : 'Save party'}</button></div><div className="panel formation-order"><b>Formation · slot order</b>{partyHeroIds.length ? partyHeroIds.map((heroId, index) => { const hero = heroCollection.find(row => row.id === heroId); return <div className="formation-row" key={heroId}><span>{index + 1}. {hero?.name ?? 'Hero'} · {hero?.heroClass ?? ''}</span><div><button className="secondary-button" aria-label="Move Hero up" disabled={index === 0 || partySaving || combatSession?.status === 'ACTIVE'} onClick={() => movePartyHero(heroId, -1)}>↑</button><button className="secondary-button" aria-label="Move Hero down" disabled={index === partyHeroIds.length - 1 || partySaving || combatSession?.status === 'ACTIVE'} onClick={() => movePartyHero(heroId, 1)}>↓</button></div></div>; }) : <p>Chọn Hero bên dưới để xếp vị trí.</p>}</div><div className="hero-grid">{heroCollection.filter(hero => hero.state !== 'DEAD' && hero.state !== 'DISABLED').map(hero => <button type="button" className={`hero-card rarity-${hero.rarity} ${partyHeroIds.includes(hero.id) ? 'selected' : ''}`} key={hero.id} disabled={combatSession?.status === 'ACTIVE'} onClick={() => togglePartyHero(hero.id)}><div className="hero-card-top"><span>{'\u2726'.repeat(Math.min(hero.rarity, 5))}</span><small>{partyHeroIds.includes(hero.id) ? 'IN PARTY' : hero.category}</small></div><div className="hero-portrait">HERO</div><h3>{hero.name}</h3><p>{hero.rarity}-star | Lv.{hero.level} | {hero.state}</p></button>)}</div>{!heroCollection.some(hero => hero.state !== 'DEAD' && hero.state !== 'DISABLED') && <div className="empty-state compact-empty"><h2>No active Heroes</h2><p>Summon a Hero before creating a party.</p></div>}</div>
          <section className="panel"><div className="panel-head"><div><div className="eyebrow">MASTER SKILL</div><h2>Kỹ năng Master</h2></div></div>{masterSkills.map(skill => <article className="template-card" key={skill.code}><h3>{skill.name}</h3><p>{skill.description}</p><p>Hồi chiêu: {skill.cooldownSeconds}s</p><button className="primary-button" disabled={combatSession?.status !== 'ACTIVE' || skillCooldown > 0 || Boolean(combatSession?.combatState?.masterSkillEffect)} onClick={() => void useMasterSkill(skill.code)}>{skillCooldown ? `Đang hồi chiêu ${skillCooldown}s` : combatSession?.combatState?.masterSkillEffect ? 'Đang hồi máu đội hình' : 'Kích hoạt'}</button></article>)}</section>
          <div className="buff-panel"><div className="panel-head"><div><div className="eyebrow">MASTER COMMAND</div><h2>Tactical Buff</h2></div><div className="cooldown-label">{combatSession?.status === 'ACTIVE' ? (cooldown ? `Cooldown ${cooldown}s` : 'Ready to switch') : 'Start a battle to activate buffs'}</div></div><div className="buff-grid">{[{ id: 'VANGUARD_RUSH', name: 'Vanguard Rush', desc: 'Attack +20% / Defense -10%', icon: 'ATK' }, { id: 'IRONCLAD_AEGIS', name: 'Ironclad Aegis', desc: 'Defense +30% / Attack -5%', icon: 'DEF' }, { id: 'SWIFT_EVASION', name: 'Swift Evasion', desc: 'Speed +25%', icon: 'SPD' }].map(b => <button key={b.id} disabled={(combatSession?.status === 'ACTIVE' && (Boolean(cooldown) || buff === b.id))} className={`buff-option ${buff === b.id ? 'selected' : ''}`} onClick={() => { if (combatSession?.status === 'ACTIVE') { void switchBuff(b.id); } else { setPreCombatBuff(b.id); } }}><span className="buff-icon">{b.icon}</span><span><b>{b.name}</b><small>{b.desc}</small></span><i>{buff === b.id ? 'ACTIVE' : cooldown ? `${cooldown}s` : 'SELECT'}</i></button>)}</div><div className="prototype-warning">{combatSession?.combatState?.floorEvent ? `${combatSession.combatState.floorEvent.name}: ${combatSession.combatState.floorEvent.description}` : 'Floor events and encounters are selected from the fixed World Seed.'} Sample event effects and enemy stats are editable prototype data.</div><div className="summon-buttons">{combatSession?.status === 'ACTIVE' ? <span className="cooldown-label">Battle advances automatically while this page is open.</span> : combatSession?.battleReport ? <div className="results-panel"><h3>Last battle: {combatSession.battleReport.result}</h3><p>Floor {combatSession.battleReport.floor} | Next floor {combatSession.battleReport.nextFloor} | Rounds: {combatSession.battleReport.rounds}</p><p>Hero EXP: {combatSession.battleReport.expReward} | Master EXP: {combatSession.battleReport.masterExpReward ?? 0} | Silver: {combatSession.battleReport.silverReward}</p>{combatSession.battleReport.masterLevelUps?.map(row => <p key={`${row.fromLevel}-${row.toLevel}`}>Master leveled up: {row.fromLevel} -&gt; {row.toLevel}</p>)}{combatSession.battleReport.floorEvent && <p>{combatSession.battleReport.floorEvent.name}: {combatSession.battleReport.floorEvent.description}</p>}{combatSession.battleReport.heroLevelUps?.map(row => <p key={row.heroId}>{row.name} leveled up: {row.fromLevel} -&gt; {row.toLevel}</p>)}{combatSession.battleReport.survivors?.length ? (
                    <p style={{ color: '#88ff88' }}>
                      Hero sống sót: {combatSession.battleReport.survivors.map(s => `${s.name} (${s.hp}/${s.maxHp} HP)`).join(', ')}
                    </p>
                  ) : null}
                  {combatSession.battleReport.fallenHeroes.map(hero => (
                    <p key={hero.name} style={{ color: hero.deathType === 'PERMADEATH' ? '#ff5555' : '#ffaa44' }}>
                      {hero.name}: {hero.deathType === 'PERMADEATH' ? 'Tử trận vĩnh viễn (Permadeath)' : 'Vô hiệu hóa (Disabled)'}
                      {hero.droppedEquipmentCount ? ` · Rơi ${hero.droppedEquipmentCount} món trang bị tại sàn` : ''}
                    </p>
                  ))}</div> : null}{combatSession?.status !== 'ACTIVE' && <button className="primary-button" disabled={!me?.world || !selectedParty || partyHeroIds.length === 0 || JSON.stringify(partyHeroIds) !== JSON.stringify(savedPartyHeroIds)} onClick={() => void startCombat()}>Start PvE battle</button>}</div></div>
          {combatSession?.status === 'ACTIVE' && combatSession.combatState && (
            <div className="panel combatants-view">
              <div className="panel-head">
                <div>
                  <div className="eyebrow">ACTIVE COMBATANTS</div>
                  <h2>Round {combatSession.combatState.round} · Floor {combatSession.combatState.floor}</h2>
                </div>
                {combatSession.combatState.strategy?.name && (
                  <span className="limited-tag">Strategy: {combatSession.combatState.strategy.name}</span>
                )}
              </div>
              <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center', margin: '0.6rem 0', flexWrap: 'wrap' }}>
                <span style={{ fontSize: '0.85rem', color: 'var(--text-muted)' }}>Chỉ huy (Target AI):</span>
                {(['BALANCED', 'LOWEST_HP', 'HIGHEST_ATK', 'FRONTLINE'] as const).map(p => (
                  <button
                    key={p}
                    type="button"
                    className={(combatSession.combatState?.targetPriority ?? 'BALANCED') === p ? 'primary-button' : 'secondary-button'}
                    style={{ padding: '0.2rem 0.6rem', fontSize: '0.75rem' }}
                    onClick={() => void changeTargetPriority(p)}
                  >
                    {p === 'BALANCED' ? 'Cân bằng' : p === 'LOWEST_HP' ? 'HP Thấp' : p === 'HIGHEST_ATK' ? 'ATK Cao' : 'Tiền tuyến'}
                  </button>
                ))}
                <button
                  type="button"
                  className="secondary-button"
                  style={{ padding: '0.2rem 0.6rem', fontSize: '0.75rem', borderColor: '#ff4444', color: '#ff7777', marginLeft: 'auto' }}
                  onClick={() => void retreatCombat()}
                >
                  Rút lui chiến thuật
                </button>
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: '1rem' }}>
                <div>
                  <b>Đội ngũ ({combatSession.combatState.heroes.filter(h => h.hp > 0).length} còn sống)</b>
                  {combatSession.combatState.heroes.map(hero => (
                    <div key={hero.id} style={{ margin: '0.4rem 0', padding: '0.4rem 0.6rem', background: 'rgba(255,255,255,0.03)', borderRadius: '4px' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <span>Vị trí {(hero.slotIndex ?? 0) + 1}: <b>{hero.name}</b> {hero.element && <small style={{ color: '#ffb' }}>[{hero.element}]</small>}</span>
                        <span style={{ color: hero.hp <= 0 ? 'red' : 'lightgreen' }}>{hero.hp}/{hero.maxHp} HP {hero.shield && hero.shield > 0 ? <b style={{ color: '#6cf' }}>(+{hero.shield} Giáp)</b> : ''}</span>
                      </div>
                      {hero.skills && hero.skills.length > 0 && (
                        <small style={{ color: 'var(--text-muted)' }}>
                          Kỹ năng: {hero.skills.map(s => `${s.name} (Lv.${s.skillLevel} [${s.behaviorMode}])`).join(', ')}
                        </small>
                      )}
                    </div>
                  ))}
                </div>
                <div>
                  <b>Kẻ địch ({combatSession.combatState.enemies.filter(e => e.hp > 0).length} còn sống)</b>
                  {combatSession.combatState.enemies.map(foe => (
                    <div key={foe.id} style={{ margin: '0.4rem 0', padding: '0.4rem 0.6rem', background: 'rgba(255,255,255,0.03)', borderRadius: '4px' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <span>Vị trí {(foe.slotIndex ?? 0) + 1}: <b>{foe.name}</b> {foe.element && <small style={{ color: '#ffb' }}>[{foe.element}]</small>}</span>
                        <span style={{ color: foe.hp <= 0 ? 'red' : 'lightcoral' }}>{foe.hp}/{foe.maxHp} HP {foe.shield && foe.shield > 0 ? <b style={{ color: '#6cf' }}>(+{foe.shield} Giáp)</b> : ''}</span>
                      </div>
                      <small style={{ color: 'var(--text-muted)' }}>ATK: {foe.attack ?? '?'} · DEF: {foe.defense ?? '?'} · SPD: {foe.speed ?? '?'}</small>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          )}
          {combatSession?.combatState?.log?.length ? <div className="results-panel"><div className="panel-head"><div><div className="eyebrow">BATTLE LOG</div><h2>Latest actions</h2></div></div>{combatSession.combatState.log.slice(-8).reverse().map((entry, i) => <p key={`${entry.round}-${i}`}>R{entry.round}: {entry.actor} hits {entry.target} for {entry.damage} | target HP {entry.targetHp}</p>)}</div> : null}
        </section>}
      </div>
      <footer className="footer"><span>INFINITE GACHA <i>·</i> PHASE 1 WEB PROTOTYPE</span><span>UTC+7 <i>·</i> PVE FIRST</span></footer>
    </main>
  </div>;
}

function AuthScreen({ onAuthenticated }: { onAuthenticated: (session: Session) => void }) {
  const [register, setRegister] = useState(false);
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [email, setEmail] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const submit = async (e: React.FormEvent) => {
    e.preventDefault(); setBusy(true); setError('');
    try {
      const result = await api<{ accountId: string; username: string; accessToken: string }>(register ? '/api/auth/register' : '/api/auth/login', undefined, { method: 'POST', body: JSON.stringify({ username, password, email }) });
      onAuthenticated({ accountId: result.accountId, username: result.username, token: result.accessToken });
    } catch (err) { setError((err as Error).message); }
    finally { setBusy(false); }
  };
  return <div className="auth-screen"><div className="auth-art"><div className="auth-rune rune-one">✧</div><div className="auth-rune rune-two">◇</div><div className="auth-orbit orbit-one" /><div className="auth-orbit orbit-two" /><div className="auth-mark">∞</div><div className="auth-title"><span>INFINITE</span><b>GACHA</b></div><p>HERO MANAGEMENT · SURVIVAL · STRATEGY</p><div className="auth-bottom-note">A WORLD SHAPED BY YOUR CHOICES</div></div><form className="auth-form" onSubmit={submit}><div className="mobile-brand">∞ <b>INFINITE GACHA</b></div><div className="eyebrow">PLAYER ACCESS</div><h1>{register ? 'Tạo tài khoản' : 'Chào mừng trở lại'}</h1><p className="auth-sub">{register ? 'Bắt đầu hành trình trong thế giới của riêng bạn.' : 'Đăng nhập để tiếp tục hành trình.'}</p><label>Tên tài khoản<input required minLength={3} maxLength={32} pattern="[A-Za-z0-9]{3,32}" autoComplete="username" value={username} onChange={e => setUsername(e.target.value)} placeholder="Tên tài khoản" /></label>{register && <label>Email <span className="optional">(không bắt buộc)</span><input type="email" autoComplete="email" value={email} onChange={e => setEmail(e.target.value)} placeholder="you@example.com" /></label>}<label>Mật khẩu<input required minLength={register ? 8 : 1} type="password" autoComplete={register ? 'new-password' : 'current-password'} value={password} onChange={e => setPassword(e.target.value)} placeholder={register ? 'Tối thiểu 8 ký tự' : 'Mật khẩu'} /></label>{error && <div className="auth-error">{error}</div>}<button disabled={busy} className="primary-button auth-submit">{busy ? 'Đang xử lý…' : register ? 'Tạo tài khoản' : 'Đăng nhập'} <span>→</span></button><div className="auth-switch">{register ? 'Đã có tài khoản?' : 'Chưa có tài khoản?'} <button type="button" onClick={() => { setRegister(!register); setError(''); }}> {register ? 'Đăng nhập' : 'Đăng ký'}</button></div><small className="auth-security">Kết nối bảo vệ bằng phiên token prototype. Không dùng dữ liệu thật trong môi trường này.</small></form></div>;
}

function MasterForm({ token, onCreated, onError }: { token: string; onCreated: () => Promise<void>; onError: (message: string) => void }) {
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  return <form className="master-form" onSubmit={async e => { e.preventDefault(); setBusy(true); onError(''); try { await api('/api/master/init', token, { method: 'POST', body: JSON.stringify({ masterName: name }) }); await onCreated(); } catch (err) { onError((err as Error).message); } finally { setBusy(false); } }}><input required maxLength={50} value={name} onChange={e => setName(e.target.value)} placeholder="Tên Master của bạn" /><button className="primary-button" disabled={busy}>{busy ? 'Đang tạo…' : 'Tạo Master →'}</button></form>;
}

function StatCard({ icon, label, value, sub, tone }: { icon: string; label: string; value: string; sub: string; tone: string }) {
  return <div className="stat-card"><span className={`stat-icon ${tone}`}>{icon}</span><div><small>{label}</small><b>{value}</b><span>{sub}</span></div><i className="stat-spark">⌁</i></div>;
}

createRoot(document.getElementById('root')!).render(<React.StrictMode><App /></React.StrictMode>);







