import { useCallback, useEffect, useState } from 'react';

const API = import.meta.env.VITE_API_BASE_URL ?? 'http://localhost:3000';

type Product = {
  code: string;
  name: string;
  description: string;
  priceLabel: string;
  gems: number;
  silver: number;
  items: { itemId: string; quantity: number }[];
};

type Transaction = {
  id: string;
  productCode: string;
  store: string;
  status: string;
  gems: number;
  priceLabel: string;
  createdAt: string;
  storeTransactionId: string | null;
};

type Me = { master: { gems: string; gemDebt: string; silverCoins: string } | null };

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
const when = (value: string) => new Date(value).toLocaleString('vi-VN');

export function PaymentPage({ token, onError, onNotice }: { token: string; onError: (message: string) => void; onNotice: (message: string) => void }) {
  const [products, setProducts] = useState<Product[]>([]);
  const [history, setHistory] = useState<Transaction[]>([]);
  const [wallet, setWallet] = useState({ gems: 0, gemDebt: 0 });
  const [store, setStore] = useState('APPLE');
  const [pending, setPending] = useState<{ transactionId: string; store: string; product: { name: string } } | null>(null);
  const [storeTransactionId, setStoreTransactionId] = useState('');
  const [receiptToken, setReceiptToken] = useState('');
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const [list, rows, me] = await Promise.all([
      call<Product[]>('/api/iap/products', token),
      call<Transaction[]>('/api/iap/transactions', token),
      call<Me>('/api/me', token),
    ]);
    setProducts(list);
    setHistory(rows);
    setWallet({ gems: Number(me.master?.gems ?? 0), gemDebt: Number(me.master?.gemDebt ?? 0) });
  }, [token]);

  useEffect(() => { load().catch(error => onError((error as Error).message)); }, [load, onError]);

  const checkout = async (product: Product) => {
    setBusy(true);
    onError('');
    try {
      const result = await call<{ transactionId: string; store: string; product: { name: string } }>('/api/iap/checkout', token, {
        method: 'POST',
        body: JSON.stringify({ productCode: product.code, store }),
      });
      setPending(result);
      onNotice(`Đã mở giao dịch ${product.name}. Nhập biên lai cửa hàng để hoàn tất.`);
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const submitReceipt = async () => {
    if (!pending) return;
    setBusy(true);
    onError('');
    try {
      const result = await call<{ gemsCredited: number; gemDebtSettled: number }>('/api/iap/receipt', token, {
        method: 'POST',
        body: JSON.stringify({ transactionId: pending.transactionId, storeTransactionId, receiptToken }),
      });
      await load();
      setPending(null);
      setStoreTransactionId('');
      setReceiptToken('');
      onNotice(`Đã xác thực biên lai: +${result.gemsCredited} Ngọc (trả nợ ${result.gemDebtSettled}).`);
    } catch (error) {
      onError((error as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return <>
    <div className="page-heading">
      <div>
        <div className="eyebrow">STORE · PHASE 2</div>
        <h1>Nạp Ngọc</h1>
        <p>Gói IAP, xác thực biên lai và xử lý Nợ Ngọc khi hoàn tiền.</p>
      </div>
      <div className="admin-actions">
        <select value={store} onChange={event => setStore(event.target.value)}>
          <option value="APPLE">APPLE</option>
          <option value="GOOGLE">GOOGLE</option>
        </select>
      </div>
    </div>

    <div className="stat-grid">
      <div className="stat-card"><span className="stat-icon violet">◆</span><div><small>Ngọc</small><b>{numberFormat.format(wallet.gems)}</b><span>số dư hiện tại</span></div></div>
      <div className="stat-card"><span className="stat-icon rose">⚑</span><div><small>Nợ Ngọc</small><b>{numberFormat.format(wallet.gemDebt)}</b><span>trừ tự động khi nạp</span></div></div>
      <div className="stat-card"><span className="stat-icon gold">▦</span><div><small>Giao dịch</small><b>{history.length}</b><span>50 gần nhất</span></div></div>
      <div className="stat-card"><span className="stat-icon blue">◈</span><div><small>Gói đang bán</small><b>{products.length}</b><span>giá tham khảo USD</span></div></div>
    </div>

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">PACKAGES</div><h2>Gói nạp</h2></div></div>
      <div className="shop-grid">
        {products.map(product => <article className="shop-card" key={product.code}>
          <header><b>{product.name}</b><em className="admin-badge">{product.priceLabel}</em></header>
          <p>{product.description}</p>
          <div className="shop-price">
            <span>{product.gems} Ngọc{product.silver ? ` · ${numberFormat.format(product.silver)} Xu` : ''}</span>
            <small>{product.items.map(row => `${row.quantity} × ${row.itemId}`).join(' · ') || 'không kèm vật phẩm'}</small>
          </div>
          <div className="shop-actions">
            <button type="button" className="primary-button" disabled={busy} onClick={() => void checkout(product)}>Mua qua {store}</button>
          </div>
        </article>)}
      </div>
    </section>

    {pending && <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">RECEIPT</div><h2>Xác thực biên lai — {pending.product.name}</h2></div></div>
      <p className="base-note">Giao dịch <code>{pending.transactionId}</code>. Prototype mô phỏng biên lai bằng HMAC-SHA256 của <code>store:storeTransactionId</code> với khoá <code>PAYMENT_GATEWAY_SECRET</code>.</p>
      <div className="admin-grid">
        <label className="admin-field">Store transaction id
          <input value={storeTransactionId} placeholder="TX_APPLE_88888" onChange={event => setStoreTransactionId(event.target.value)} />
        </label>
        <label className="admin-field">Receipt token (HMAC)
          <input value={receiptToken} placeholder="hex" onChange={event => setReceiptToken(event.target.value)} />
        </label>
      </div>
      <div className="admin-actions">
        <button type="button" className="primary-button" disabled={busy || !storeTransactionId || !receiptToken} onClick={() => void submitReceipt()}>Xác thực &amp; nhận hàng</button>
        <button type="button" className="text-button" disabled={busy} onClick={() => setPending(null)}>Huỷ</button>
      </div>
    </section>}

    <section className="panel">
      <div className="panel-head"><div><div className="eyebrow">HISTORY</div><h2>Lịch sử giao dịch</h2></div></div>
      <div className="admin-table">
        <div className="admin-row admin-row-head"><span>Gói</span><span>Store</span><span>Ngọc</span><span>Trạng thái</span><span>Thời điểm</span></div>
        {history.length === 0 && <div className="admin-row"><span>Chưa có giao dịch.</span></div>}
        {history.map(row => <div className="admin-row" key={row.id}>
          <span>{row.productCode}<small className="admin-muted">{row.priceLabel}</small></span>
          <span>{row.store}</span>
          <span>{numberFormat.format(row.gems)}</span>
          <span><em className={`admin-badge ${row.status === 'COMPLETED' ? 'ok' : row.status === 'REFUNDED' ? 'danger' : 'warn'}`}>{row.status}</em></span>
          <span>{when(row.createdAt)}</span>
        </div>)}
      </div>
    </section>
  </>;
}
