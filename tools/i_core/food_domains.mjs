import { validBusinessDate, validBusinessTime } from './personal_data_domains.mjs';

export const FOOD_HOOK_VERSION = 'food-v1';
export const FOOD_DOMAINS = ['food_entries'];

const field = (type, values) => ({
  type,
  required: true,
  ...(values ? {enum: values} : {}),
});

export const FOOD_SCHEMAS = {
  food_entries: {
    version: 1,
    fields: {
      eaten_at: field('string'),
      local_date: field('string'),
      meal: field('string', ['breakfast', 'lunch', 'dinner', 'snack', 'drink']),
      title: field('string'),
      note: field('string'),
      input_kind: field('string', ['photo', 'text', 'mixed', 'app']),
      items: field('array'),
      totals: field('object'),
      user_corrected: field('boolean'),
      voided: field('boolean'),
    },
  },
};

const MEALS = FOOD_SCHEMAS.food_entries.fields.meal.enum;
const INPUT_KINDS = FOOD_SCHEMAS.food_entries.fields.input_kind.enum;
const FOOD_SOURCES = ['model', 'label', 'personal', 'usda'];
const BASES = ['weighed', 'label', 'photo', 'described', 'model_guess'];
const CONFIDENCES = ['high', 'medium', 'low'];
const RECORD_FIELDS = Object.keys(FOOD_SCHEMAS.food_entries.fields);
const ITEM_FIELDS = ['name', 'food_ref', 'grams', 'grams_low', 'grams_high', 'kcal', 'protein_g', 'fat_g', 'carb_g', 'basis', 'confidence'];
const FOOD_REF_FIELDS = ['source', 'id'];
const TOTAL_FIELDS = ['kcal', 'kcal_low', 'kcal_high', 'protein_g', 'fat_g', 'carb_g'];

const plain = value => value !== null && typeof value === 'object' && !Array.isArray(value)
  && Object.getPrototypeOf(value) === Object.prototype;
const exact = (value, keys) => plain(value) && keys.every(key => Object.hasOwn(value, key))
  && Object.keys(value).every(key => keys.includes(key));
const identifier = value => typeof value === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,199}$/.test(value);
const finiteRange = (value, minimum, maximum) => typeof value === 'number' && Number.isFinite(value)
  && value >= minimum && value <= maximum;
const round1 = value => Math.round(value * 10) / 10;

export function foodTotals(items) {
  return {
    kcal: round1(items.reduce((sum, item) => sum + item.kcal, 0)),
    kcal_low: round1(items.reduce((sum, item) => sum + item.kcal * item.grams_low / item.grams, 0)),
    kcal_high: round1(items.reduce((sum, item) => sum + item.kcal * item.grams_high / item.grams, 0)),
    protein_g: round1(items.reduce((sum, item) => sum + item.protein_g, 0)),
    fat_g: round1(items.reduce((sum, item) => sum + item.fat_g, 0)),
    carb_g: round1(items.reduce((sum, item) => sum + item.carb_g, 0)),
  };
}

function validItem(item) {
  if (!exact(item, ITEM_FIELDS) || typeof item.name !== 'string' || item.name.trim().length === 0
    || item.name.length > 100 || !exact(item.food_ref, FOOD_REF_FIELDS)
    || !FOOD_SOURCES.includes(item.food_ref.source)
    || !(item.food_ref.id === null || typeof item.food_ref.id === 'string')
    || !finiteRange(item.grams, Number.MIN_VALUE, 5000)
    || !finiteRange(item.grams_low, Number.MIN_VALUE, 5000)
    || !finiteRange(item.grams_high, Number.MIN_VALUE, 5000)
    || item.grams_low > item.grams || item.grams > item.grams_high
    || !['kcal', 'protein_g', 'fat_g', 'carb_g'].every(key => finiteRange(item[key], 0, 10000))
    || !BASES.includes(item.basis) || !CONFIDENCES.includes(item.confidence)) return false;
  return true;
}

export function validateFoodRecord(record) {
  if (!plain(record) || !identifier(record.id) || record.deleted_at) return false;
  const data = record.data;
  if (!exact(data, RECORD_FIELDS) || !validBusinessTime(data.eaten_at)
    || !validBusinessDate(data.local_date) || !MEALS.includes(data.meal)
    || typeof data.title !== 'string' || data.title.trim().length === 0 || data.title.length > 200
    || typeof data.note !== 'string' || data.note.length > 2000
    || !INPUT_KINDS.includes(data.input_kind) || !Array.isArray(data.items)
    || data.items.length < 1 || data.items.length > 40 || !data.items.every(validItem)
    || !exact(data.totals, TOTAL_FIELDS)
    || typeof data.user_corrected !== 'boolean' || typeof data.voided !== 'boolean') return false;
  const expected = foodTotals(data.items);
  return TOTAL_FIELDS.every(key => typeof data.totals[key] === 'number'
    && Number.isFinite(data.totals[key]) && data.totals[key] === expected[key]);
}

export function createFoodDomainHooks({writerPrincipalIds = []} = {}) {
  const writers = new Set(writerPrincipalIds);
  return {
    food_entries: {
      version: FOOD_HOOK_VERSION,
      authorizeOperation(ctx) {
        const principalId = ctx.principal.principal_id;
        if (!writers.has(principalId)) return false;
        if (ctx.phase === 'lookup') {
          const operation = ctx.operation;
          return operation?.actor === 'agent_inferred' && ['create', 'patch'].includes(operation.kind);
        }
        const request = ctx.request;
        if (request?.actor !== 'agent_inferred' || !['create', 'patch'].includes(request.kind)) return false;
        if (request.kind === 'create') return true;
        return ctx.phase === 'preflight' || ctx.current?.origin?.principal_id === principalId;
      },
      validateTransition({next}) {
        return validateFoodRecord(next);
      },
    },
  };
}

export function registerFoodDomains(store, {mode = 'off'} = {}) {
  for (const domain of FOOD_DOMAINS) {
    store.registerDomain(domain, structuredClone(FOOD_SCHEMAS[domain]), {
      mode,
      requiredHooksVersion: FOOD_HOOK_VERSION,
    });
  }
}
