-- ============================================================
-- 強腦力金流：orders 欄位補強（可重複執行）
-- 搭配 Edge Functions: pay-create / pay-webhook
-- ============================================================
alter table public.orders add column if not exists currency text not null default 'TWD';
alter table public.orders add column if not exists paid_at timestamptz;
create index if not exists orders_provider_order_id_idx on public.orders(provider_order_id);
alter table public.orders enable row level security;
do $$ begin
  create policy orders_self_read on public.orders for select using ( auth.uid() = user_id or public.is_admin() );
exception when duplicate_object then null; end $$;

-- 金鑰（全部放 Edge Function Secrets，不進版本庫）：
--   STRIPE_SECRET_KEY      sk_live_…（或 sk_test_… 先測試）
--   STRIPE_WEBHOOK_SECRET  whsec_…（Stripe Dashboard → Webhooks 端點的 Signing secret）
--   PAYUNI_MER_ID / PAYUNI_HASH_KEY / PAYUNI_HASH_IV / PAYUNI_ENV(sandbox|prod)
