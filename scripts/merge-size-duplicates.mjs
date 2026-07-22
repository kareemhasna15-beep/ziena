#!/usr/bin/env node
/*
 * merge-size-duplicates.mjs
 *
 * Find products whose only real difference is size (e.g. "Glass jug 1.5 liter"
 * vs "Glass jug 2 liter") and merge them into a single variant family so the
 * storefront shows ONE card with a size picker.
 *
 * USAGE
 *   SUPABASE_URL=https://xxxxx.supabase.co \
 *   SUPABASE_SERVICE_KEY=eyJhbGc...      \
 *   node scripts/merge-size-duplicates.mjs           # dry-run, writes merge-report.json
 *
 *   SUPABASE_URL=... SUPABASE_SERVICE_KEY=... \
 *   node scripts/merge-size-duplicates.mjs --apply   # actually mutate rows
 *
 * SAFETY
 *   - Only touches products where variant_group IS NULL. Existing families
 *     are never re-grouped or renamed.
 *   - Only writes variant_group, variant_label_en, variant_label_ar,
 *     variant_order, en, ar. Never touches prices, images, SKUs, discounts.
 *   - Dry-run is the default. --apply is required to write to the DB.
 *   - Ambiguous groups (two rows normalize to the same base but their size
 *     tokens are identical/missing) are moved to a "needs human review"
 *     section and NEVER auto-merged.
 */

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY  = process.env.SUPABASE_SERVICE_KEY;
const APPLY        = process.argv.includes('--apply');

if(!SUPABASE_URL || !SERVICE_KEY){
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_KEY in env.');
  console.error('  export SUPABASE_URL=https://xxxxx.supabase.co');
  console.error('  export SUPABASE_SERVICE_KEY=<service_role_key>');
  process.exit(1);
}

const REST = SUPABASE_URL.replace(/\/$/,'') + '/rest/v1';
const headers = {
  'apikey': SERVICE_KEY,
  'Authorization': 'Bearer ' + SERVICE_KEY,
  'Content-Type': 'application/json',
  'Prefer': 'return=representation'
};

async function sbGet(path){
  const r = await fetch(REST + path, { headers });
  if(!r.ok) throw new Error(`GET ${path} → ${r.status} ${await r.text()}`);
  return r.json();
}
async function sbPatch(path, body){
  const r = await fetch(REST + path, { method:'PATCH', headers, body: JSON.stringify(body) });
  if(!r.ok) throw new Error(`PATCH ${path} → ${r.status} ${await r.text()}`);
  return r.json();
}

/* ─────────────── Normalization & size-token extraction ─────────────── */

/* Size tokens we recognize inside product names, in both languages. Order
   matters for the regex — longer/units-first patterns are tried first. */
const SIZE_TOKEN_RX = new RegExp([
  /(\d+(?:[.,]\d+)?)\s*(l(?:iter|itre)?|ltr|ml|cm|mm)\b/i.source,          // 1.5 L, 500 ml, 12 cm
  /(\d+(?:[.,]\d+)?)\s*(لتر|مل|سم)\b/.source,                              // Arabic units
  /\b(small|medium|large|xl|xxl|s|m|l)\b/i.source,                         // word sizes EN
  /\b(صغير|صغيرة|وسط|متوسط|متوسطة|كبير|كبيرة)\b/.source                    // word sizes AR
].join('|'), 'gi');

/* Separators to strip (dashes and " × " variants) after size removal. */
const SEP_RX = /\s*[—\-–]\s*|\s{2,}/g;

/* Category words that carry size intent but aren't size tokens themselves. */
const NAME_STOP_RX = /\b(size|volume|version|edition)\b/gi;

/* Word-size canonical form for sort order (S<M<L<XL). */
const WORD_SIZE_ORDER = {
  s:1, small:1, صغير:1, صغيرة:1,
  m:2, medium:2, وسط:2, متوسط:2, متوسطة:2,
  l:3, large:3, كبير:3, كبيرة:3,
  xl:4,
  xxl:5
};

function toBaseName(str){
  if(!str) return '';
  let s = String(str).toLowerCase();
  s = s.replace(SIZE_TOKEN_RX, ' ');
  s = s.replace(NAME_STOP_RX, ' ');
  s = s.replace(SEP_RX, ' ');
  s = s.replace(/\s+/g, ' ').trim();
  return s;
}

/* Extract the raw size token as it appears in the ORIGINAL name (so we can
   present it back to the customer verbatim: "1.5 L", not "1.5 liter"). */
function extractSizeToken(str){
  if(!str) return null;
  SIZE_TOKEN_RX.lastIndex = 0;
  const m = SIZE_TOKEN_RX.exec(String(str));
  if(!m) return null;
  return m[0].trim();
}

/* Numeric magnitude used for sort. Returns +Infinity for non-numeric (word)
   sizes so numeric sizes sort first; word sizes fall back to WORD_SIZE_ORDER. */
function sortWeight(token){
  if(!token) return { primary: Infinity, secondary: Infinity };
  const num = token.match(/(\d+(?:[.,]\d+)?)/);
  if(num){
    return { primary: 0, secondary: parseFloat(num[1].replace(',','.')) };
  }
  const key = token.toLowerCase().trim();
  const w = WORD_SIZE_ORDER[key];
  return { primary: 1, secondary: w != null ? w : 9 };
}
function cmpWeights(a, b){
  if(a.primary !== b.primary) return a.primary - b.primary;
  return a.secondary - b.secondary;
}

/* Slug used for the shared variant_group tag. */
function slug(s){
  return String(s||'').toLowerCase()
    .normalize('NFKD').replace(/[̀-ͯ]/g,'')
    .replace(/[^a-z0-9]+/g,'-').replace(/(^-|-$)/g,'') || 'family';
}

/* ─────────────── Grouping ─────────────── */

function groupProducts(rows){
  const groups = new Map();
  for(const row of rows){
    if(row.variant_group) continue;                    // already grouped
    const baseEn = toBaseName(row.en);
    const baseAr = toBaseName(row.ar);
    if(!baseEn && !baseAr) continue;                   // nothing to normalize
    /* Group key = normalized EN base + category. AR only participates as a
       secondary confirmation to avoid cross-family collisions when EN alone
       is generic (e.g. "jar"). */
    const key = `${row.category || '_'}::${baseEn}::${baseAr}`;
    const bucket = groups.get(key) || { key, category: row.category, baseEn, baseAr, members: [] };
    bucket.members.push(row);
    groups.set(key, bucket);
  }
  return [...groups.values()].filter(g => g.members.length > 1);
}

/* Attach extracted size tokens + sort weights. Split into merge-ready vs
   needs-review depending on whether every member has a distinct token. */
function planMerges(groups){
  const merges = [];
  const review = [];
  for(const g of groups){
    const members = g.members.map(m => {
      const tokEn = extractSizeToken(m.en);
      const tokAr = extractSizeToken(m.ar);
      const token = tokEn || tokAr || null;
      return { row: m, tokenEn: tokEn, tokenAr: tokAr, token, weight: sortWeight(token) };
    });
    const tokens = members.map(m => (m.token || '').toLowerCase());
    const missing = tokens.filter(t => !t).length;
    const unique = new Set(tokens);
    /* Ambiguity: any member missing a token, OR duplicate tokens across the
       group. Either way, refuse to auto-merge. */
    if(missing > 0 || unique.size !== members.length){
      review.push({ ...g, members, reason: missing > 0 ? 'missing size token(s)' : 'duplicate size tokens' });
      continue;
    }
    members.sort((a,b) => cmpWeights(a.weight, b.weight));
    merges.push({ ...g, members });
  }
  return { merges, review };
}

/* ─────────────── Report ─────────────── */

function summarizeGroup(g){
  return {
    base_en: g.baseEn,
    base_ar: g.baseAr,
    category: g.category,
    variant_group_will_be: slug(g.baseEn || g.baseAr),
    members: g.members.map(m => ({
      id: m.row.id,
      sku: m.row.sku || null,
      en: m.row.en,
      ar: m.row.ar,
      price: m.row.price,
      size_token: m.token,
      rewritten_en: g.baseEn && m.token ? `${m.row.en.replace(/\s+/g,' ').trim()}` : m.row.en,
      variant_label_en_will_be: m.tokenEn || m.token,
      variant_label_ar_will_be: m.tokenAr || m.token
    }))
  };
}

function summarizeReview(g){
  return {
    base_en: g.baseEn,
    base_ar: g.baseAr,
    category: g.category,
    reason: g.reason,
    members: g.members.map(m => ({
      id: m.row.id,
      sku: m.row.sku || null,
      en: m.row.en,
      ar: m.row.ar,
      size_token: m.token
    }))
  };
}

function buildRewrittenName(originalName, sizeToken){
  /* Build "<base name> — <label>" using the original name's casing for the
     base and the extracted size token verbatim for the label. Falls back to
     "<original> — <label>" if we can't cleanly strip the token. */
  if(!originalName) return originalName;
  const base = String(originalName)
    .replace(SIZE_TOKEN_RX, ' ')
    .replace(NAME_STOP_RX, ' ')
    .replace(SEP_RX, ' ')
    .replace(/\s+/g, ' ').trim();
  if(!base) return originalName;
  return `${base} — ${sizeToken}`;
}

/* ─────────────── Main ─────────────── */

async function main(){
  console.log(`\nMerge-size-duplicates — ${APPLY ? 'APPLY' : 'DRY-RUN'}`);
  console.log(`Fetching products from ${SUPABASE_URL}…`);
  /* PostgREST returns max 1000 rows/page by default. Loop until fewer than
     that come back so we handle catalogs larger than the default cap. */
  const rows = [];
  const pageSize = 1000;
  for(let from=0; ; from+=pageSize){
    const to = from + pageSize - 1;
    const page = await fetch(`${REST}/products?variant_group=is.null&select=id,sku,en,ar,category,price,variant_group&order=id.asc`, {
      headers: { ...headers, 'Range-Unit': 'items', 'Range': `${from}-${to}` }
    }).then(r => r.ok ? r.json() : Promise.reject(new Error(`fetch failed: ${r.status}`)));
    rows.push(...page);
    if(page.length < pageSize) break;
  }
  console.log(`Fetched ${rows.length} ungrouped products.\n`);

  const groups = groupProducts(rows);
  const { merges, review } = planMerges(groups);

  const report = {
    generated_at: new Date().toISOString(),
    mode: APPLY ? 'apply' : 'dry-run',
    total_ungrouped: rows.length,
    merge_group_count: merges.length,
    merge_row_count: merges.reduce((n,g)=>n+g.members.length, 0),
    review_group_count: review.length,
    merges: merges.map(summarizeGroup),
    needs_human_review: review.map(summarizeReview)
  };

  /* Human-readable console output. */
  console.log(`Found ${merges.length} merge-ready group(s) covering ${report.merge_row_count} row(s).`);
  for(const g of merges){
    console.log(`\n  ▸ ${g.baseEn || g.baseAr}  [category: ${g.category || '—'}]`);
    console.log(`    → variant_group: ${slug(g.baseEn || g.baseAr)}`);
    for(const m of g.members){
      const priceTxt = m.row.price != null ? `$${m.row.price}` : '—';
      console.log(`      · #${m.row.id}  ${m.row.sku || '(no sku)'}  "${m.row.en}"  size="${m.token}"  price=${priceTxt}`);
    }
  }
  if(review.length){
    console.log(`\n${review.length} group(s) NEED HUMAN REVIEW:`);
    for(const g of review){
      console.log(`\n  ⚠ ${g.baseEn || g.baseAr}  (${g.reason})`);
      for(const m of g.members){
        console.log(`      · #${m.row.id}  "${m.row.en}"  token="${m.token || '—'}"`);
      }
    }
  }

  /* Always write the report file so the admin has a paper trail. */
  const fs = await import('node:fs/promises');
  const path = await import('node:path');
  const outPath = path.resolve(process.cwd(), 'merge-report.json');
  await fs.writeFile(outPath, JSON.stringify(report, null, 2), 'utf8');
  console.log(`\nWrote report → ${outPath}`);

  if(!APPLY){
    console.log('\nDry-run only. Re-run with --apply to write the changes above.');
    return;
  }

  /* APPLY mode. Idempotent: only PATCH rows that don't already have a
     variant_group set, and never touch review groups. */
  console.log('\nApplying merges…');
  let updated = 0;
  for(const g of merges){
    const group = slug(g.baseEn || g.baseAr);
    for(let ix=0; ix<g.members.length; ix++){
      const m = g.members[ix];
      /* Re-check freshness — if another process assigned a variant_group
         between the fetch and now, skip. */
      const fresh = await sbGet(`/products?id=eq.${m.row.id}&select=id,variant_group`);
      if(!fresh.length || fresh[0].variant_group){
        console.log(`  · #${m.row.id} skipped (already grouped)`);
        continue;
      }
      const patch = {
        variant_group: group,
        variant_label_en: m.tokenEn || m.token,
        variant_label_ar: m.tokenAr || m.token,
        variant_order: ix + 1,
        en: buildRewrittenName(m.row.en, m.tokenEn || m.token),
        ar: m.row.ar ? buildRewrittenName(m.row.ar, m.tokenAr || m.token) : null
      };
      await sbPatch(`/products?id=eq.${m.row.id}`, patch);
      updated++;
      console.log(`  ✓ #${m.row.id}  → ${group}  [${patch.variant_label_en}]  order=${ix+1}`);
    }
  }
  console.log(`\nDone. Updated ${updated} row(s) across ${merges.length} group(s).`);
  if(review.length){
    console.log(`${review.length} group(s) were left untouched — see the "needs_human_review" section of merge-report.json.`);
  }
}

main().catch(e => { console.error('\nFATAL:', e); process.exit(2); });
