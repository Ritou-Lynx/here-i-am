/// Domain schema definitions for SharedLife entities.
///
/// Each domain declares recommended field names, types, and enum constraints.
/// The DomainSchemaValidator uses these to validate and normalize patches
/// before they are written to SharedLifeEventOperations.
library;

enum DomainFieldType { string, number, datetime, boolean, enumType }

class DomainFieldDef {
  const DomainFieldDef({
    required this.name,
    required this.type,
    this.required = false,
    this.enumValues,
  });

  final String name;
  final DomainFieldType type;
  final bool required;

  /// Only set when [type] == [DomainFieldType.enumType].
  final List<String>? enumValues;
}

class DomainSchema {
  const DomainSchema({
    required this.domain,
    required this.version,
    required this.fields,
  });

  final String domain;
  final int version;
  final List<DomainFieldDef> fields;

  Set<String> get fieldNames => {for (final f in fields) f.name};
}

// ── Domain definitions ─────────────────────────────────────────────────────

const domainHealth = DomainSchema(
  domain: 'health',
  version: 1,
  fields: [
    DomainFieldDef(name: 'activity_type', type: DomainFieldType.string),
    DomainFieldDef(name: 'duration_minutes', type: DomainFieldType.number),
    DomainFieldDef(name: 'distance_km', type: DomainFieldType.number),
    DomainFieldDef(name: 'calories', type: DomainFieldType.number),
    DomainFieldDef(name: 'steps', type: DomainFieldType.number),
    DomainFieldDef(name: 'sleep_hours', type: DomainFieldType.number),
    DomainFieldDef(name: 'sleep_quality', type: DomainFieldType.enumType,
        enumValues: ['poor', 'fair', 'good', 'excellent']),
    DomainFieldDef(name: 'weight_kg', type: DomainFieldType.number),
    DomainFieldDef(name: 'food', type: DomainFieldType.string),
    DomainFieldDef(name: 'notes', type: DomainFieldType.string),
  ],
);

const domainFinance = DomainSchema(
  domain: 'finance',
  version: 1,
  fields: [
    DomainFieldDef(name: 'amount', type: DomainFieldType.number, required: true),
    DomainFieldDef(name: 'currency', type: DomainFieldType.string),
    DomainFieldDef(
      name: 'direction',
      type: DomainFieldType.enumType,
      required: true,
      enumValues: ['expense', 'income', 'transfer'],
    ),
    DomainFieldDef(name: 'category', type: DomainFieldType.string),
    DomainFieldDef(name: 'merchant', type: DomainFieldType.string),
    DomainFieldDef(name: 'payment_method', type: DomainFieldType.string),
    DomainFieldDef(name: 'notes', type: DomainFieldType.string),
  ],
);

const domainSchedule = DomainSchema(
  domain: 'schedule',
  version: 1,
  fields: [
    DomainFieldDef(name: 'location', type: DomainFieldType.string),
    DomainFieldDef(name: 'participants', type: DomainFieldType.string),
    DomainFieldDef(name: 'reminder_minutes', type: DomainFieldType.number),
    DomainFieldDef(name: 'recurrence', type: DomainFieldType.enumType,
        enumValues: ['none', 'daily', 'weekly', 'monthly']),
    DomainFieldDef(name: 'notes', type: DomainFieldType.string),
  ],
);

const domainTask = DomainSchema(
  domain: 'task',
  version: 1,
  fields: [
    DomainFieldDef(name: 'priority', type: DomainFieldType.enumType,
        enumValues: ['low', 'medium', 'high', 'urgent']),
    DomainFieldDef(name: 'project', type: DomainFieldType.string),
    DomainFieldDef(name: 'due_at', type: DomainFieldType.datetime),
    DomainFieldDef(name: 'assignee', type: DomainFieldType.string),
    DomainFieldDef(name: 'notes', type: DomainFieldType.string),
  ],
);

const domainSocial = DomainSchema(
  domain: 'social',
  version: 1,
  fields: [
    DomainFieldDef(name: 'people', type: DomainFieldType.string),
    DomainFieldDef(name: 'venue', type: DomainFieldType.string),
    DomainFieldDef(name: 'activity', type: DomainFieldType.string),
    DomainFieldDef(name: 'notes', type: DomainFieldType.string),
  ],
);

const domainInterest = DomainSchema(
  domain: 'interest',
  version: 1,
  fields: [
    DomainFieldDef(name: 'content_type', type: DomainFieldType.enumType,
        enumValues: ['book', 'article', 'movie', 'series', 'game', 'music', 'podcast', 'other']),
    DomainFieldDef(name: 'title', type: DomainFieldType.string),
    DomainFieldDef(name: 'author', type: DomainFieldType.string),
    DomainFieldDef(name: 'rating', type: DomainFieldType.number),
    DomainFieldDef(name: 'progress', type: DomainFieldType.string),
    DomainFieldDef(name: 'notes', type: DomainFieldType.string),
  ],
);

const domainClothing = DomainSchema(
  domain: 'clothing',
  version: 1,
  fields: [
    DomainFieldDef(name: 'outfit', type: DomainFieldType.string),
    DomainFieldDef(name: 'occasion', type: DomainFieldType.string),
    DomainFieldDef(name: 'weather', type: DomainFieldType.string),
    DomainFieldDef(name: 'notes', type: DomainFieldType.string),
  ],
);

const domainGeneral = DomainSchema(
  domain: 'general',
  version: 1,
  fields: [
    DomainFieldDef(name: 'notes', type: DomainFieldType.string),
  ],
);

/// Index of all domain schemas keyed by domain name.
const Map<String, DomainSchema> allDomainSchemas = {
  'health': domainHealth,
  'finance': domainFinance,
  'schedule': domainSchedule,
  'task': domainTask,
  'social': domainSocial,
  'interest': domainInterest,
  'clothing': domainClothing,
  'general': domainGeneral,
};

/// All supported domain names.
const supportedDomains = {
  'health',
  'finance',
  'schedule',
  'task',
  'social',
  'interest',
  'clothing',
  'general',
};
