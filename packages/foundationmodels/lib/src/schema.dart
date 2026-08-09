/// `FmSchema` — a typed builder that emits **exactly** the JSON-Schema
/// subset accepted by the Swift core's `DynamicGenerationSchema` converter
/// (upstream ADR-0008, `docs/schema-contract.md`).
///
/// ## The subset
///
/// Types: `object` (with `properties` / `required` /
/// `additionalProperties: false`), `array` (with `items`, optional
/// `minItems` / `maxItems`), `string` (optional `enum`), `number`,
/// `integer`, `boolean`; optional `description` on any node; `$defs` only
/// via [FmSchema.withDefs]; `$ref` only to internal `#/\$defs/...` targets.
///
/// ## Output vs. tool modes (upstream nuance — verbatim in spirit)
///
/// - [SchemaMode.output] (default): **fail-fast**. Any out-of-subset keyword
///   throws [UnsupportedSchemaTypeException] locally, naming the keyword and
///   the JSON-Pointer [path] — *before* any native call, so no model
///   invocation is wasted on a schema the core would reject anyway.
/// - [SchemaMode.tool]: **sanitize**. Out-of-subset keywords are silently
///   stripped when serializing tool parameters (mirroring upstream:
///   "tools: sanitize; outputs: reject").
///
/// ## Strict / repair
///
/// `strict` is the default for guided output: the model's structured output
/// must validate. `repair` allows a best-effort fix-up pass; it is carried
/// as metadata and enforced by the native core in a later phase — the Dart
/// side only forwards it.
library;

import 'package:foundationmodels_platform_interface/foundationmodels_platform_interface.dart';

/// How a schema is serialized and validated.
enum SchemaMode {
  /// Guided output: reject out-of-subset keywords (fail-fast, local).
  output,

  /// Tool parameters: strip out-of-subset keywords at the edge.
  tool,
}

/// A guided-generation schema node.
///
/// Use the factories: [FmSchema.object], [FmSchema.array],
/// [FmSchema.string], [FmSchema.number], [FmSchema.integer],
/// [FmSchema.boolean], [FmSchema.ref], [FmSchema.raw].
sealed class FmSchema {
  const FmSchema._();

  /// An object schema with named [properties].
  ///
  /// [required] lists mandatory property names; [additionalProperties]
  /// defaults to `false` (the only supported value upstream).
  static FmObjectSchema object(
    Map<String, FmSchema> properties, {
    List<String> required = const [],
    bool additionalProperties = false,
    String? description,
  }) =>
      FmObjectSchema._(
        properties: properties,
        required: required,
        additionalProperties: additionalProperties,
        description: description,
      );

  /// An array schema over [items].
  static FmArraySchema array(
    FmSchema items, {
    int? minItems,
    int? maxItems,
    String? description,
  }) =>
      FmArraySchema._(
        items: items,
        minItems: minItems,
        maxItems: maxItems,
        description: description,
      );

  /// A string schema, optionally constrained to [enumValues].
  static FmStringSchema string({
    List<String>? enumValues,
    String? description,
  }) =>
      FmStringSchema._(enumValues: enumValues, description: description);

  /// A number schema.
  static FmLeafSchema number({String? description}) =>
      FmLeafSchema._('number', description: description);

  /// An integer schema.
  static FmLeafSchema integer({String? description}) =>
      FmLeafSchema._('integer', description: description);

  /// A boolean schema.
  static FmLeafSchema boolean({String? description}) =>
      FmLeafSchema._('boolean', description: description);

  /// A reference to an internal `#/\$defs/<name>` definition.
  ///
  /// External refs (URLs, file paths) throw
  /// [UnsupportedSchemaTypeException] immediately — the upstream
  /// `external_ref` sub-case.
  static FmRefSchema ref(String name) => FmRefSchema._(name);

  /// A raw JSON-Schema map (escape hatch).
  ///
  /// Validated against the subset at [toJson] time in [SchemaMode.output]
  /// (fail-fast) and sanitized in [SchemaMode.tool].
  static FmRawSchema raw(Map<String, Object?> json) => FmRawSchema._(json);

  /// Wraps [root] with `$defs` for internal references.
  static FmDefsSchema withDefs(
    Map<String, FmSchema> defs,
    FmSchema root,
  ) =>
      FmDefsSchema._(defs: defs, root: root);

  /// Serializes to JSON Schema per [mode] (see [SchemaMode]).
  ///
  /// In [SchemaMode.output], throws [UnsupportedSchemaTypeException] on any
  /// out-of-subset construct, with `path` set to the JSON Pointer of the
  /// offending node.
  Map<String, Object?> toJson({SchemaMode mode = SchemaMode.output}) {
    return _toJson(mode: mode, path: '');
  }

  /// Internal serializer tracking the JSON-Pointer [path] for errors.
  Map<String, Object?> _toJson({required SchemaMode mode, required String path});

  /// Validates a raw JSON-Schema node against the subset.
  ///
  /// Throws [UnsupportedSchemaTypeException] (fail-fast) in
  /// [SchemaMode.output]; silently drops out-of-subset keywords in
  /// [SchemaMode.tool].
  static Map<String, Object?> validateRaw(
    Map<String, Object?> node, {
    required SchemaMode mode,
    required String path,
  }) {
    const supported = {
      'type',
      'properties',
      'required',
      'additionalProperties',
      'items',
      'minItems',
      'maxItems',
      'enum',
      'description',
      '\$defs',
      '\$ref',
    };
    final out = <String, Object?>{};
    for (final entry in node.entries) {
      if (!supported.contains(entry.key)) {
        if (mode == SchemaMode.output) {
          throw UnsupportedSchemaTypeException(
            message: 'Unsupported JSON Schema keyword "${entry.key}" at '
                '"${path.isEmpty ? '/' : path}". The FoundationModels core '
                'accepts only the documented subset (types, properties, '
                'required, additionalProperties:false, items, min/maxItems, '
                'enum, description, internal \$defs/\$ref).',
            keyword: entry.key,
            path: path.isEmpty ? '/' : path,
            schemaErrorCase: 'unsupported_keyword',
          );
        }
        continue; // tool mode: strip.
      }
      out[entry.key] = entry.value;
    }

    // Recurse into known composite fields.
    void recurse(String key) {
      final value = out[key];
      if (value is Map<String, Object?>) {
        out[key] = validateRaw(value, mode: mode, path: '$path/$key');
      }
    }

    recurse('items');
    final properties = out['properties'];
    if (properties is Map<String, Object?>) {
      out['properties'] = properties.map(
        (name, child) => MapEntry(
          name,
          child is Map<String, Object?>
              ? validateRaw(child, mode: mode, path: '$path/properties/$name')
              : child,
        ),
      );
    }
    final defs = out['\$defs'];
    if (defs is Map<String, Object?>) {
      out['\$defs'] = defs.map(
        (name, child) => MapEntry(
          name,
          child is Map<String, Object?>
              ? validateRaw(child, mode: mode, path: '$path/\$defs/$name')
              : child,
        ),
      );
    }

    // additionalProperties must be exactly false in output mode.
    final additional = out['additionalProperties'];
    if (additional != null && additional != false) {
      if (mode == SchemaMode.output) {
        throw UnsupportedSchemaTypeException(
          message: 'additionalProperties must be `false` at '
              '"${path.isEmpty ? '/' : path}" (the core only supports '
              'closed objects).',
          keyword: 'additionalProperties',
          path: path.isEmpty ? '/' : path,
          schemaErrorCase: 'additional_properties_true',
        );
      }
      out['additionalProperties'] = false;
    }

    // External refs are never supported.
    final ref = out['\$ref'];
    if (ref is String && !ref.startsWith('#/\$defs/')) {
      if (mode == SchemaMode.output) {
        throw UnsupportedSchemaTypeException(
          message: 'External \$ref "$ref" at "${path.isEmpty ? '/' : path}" '
              'is not supported; only internal "#/\$defs/..." references.',
          keyword: '\$ref',
          path: path.isEmpty ? '/' : path,
          schemaErrorCase: 'external_ref',
        );
      }
      out.remove('\$ref');
    }
    return out;
  }
}

/// Object node (see [FmSchema.object]).
final class FmObjectSchema extends FmSchema {
  const FmObjectSchema._({
    required this.properties,
    required this.required,
    required this.additionalProperties,
    this.description,
  }) : super._();

  /// Named child schemas.
  final Map<String, FmSchema> properties;

  /// Mandatory property names.
  final List<String> required;

  /// Closed-object flag; the core only supports `false`.
  final bool additionalProperties;

  /// Optional node description.
  final String? description;

  @override
  Map<String, Object?> _toJson({
    required SchemaMode mode,
    required String path,
  }) {
    if (additionalProperties != false && mode == SchemaMode.output) {
      throw UnsupportedSchemaTypeException(
        message: 'additionalProperties must be `false` at '
            '"${path.isEmpty ? '/' : path}".',
        keyword: 'additionalProperties',
        path: path.isEmpty ? '/' : path,
        schemaErrorCase: 'additional_properties_true',
      );
    }
    return {
      'type': 'object',
      'properties': properties.map(
        (name, schema) =>
            MapEntry(name, schema._toJson(mode: mode, path: '$path/properties/$name')),
      ),
      if (required.isNotEmpty) 'required': required,
      'additionalProperties': false,
      if (description != null) 'description': description,
    };
  }
}

/// Array node (see [FmSchema.array]).
final class FmArraySchema extends FmSchema {
  const FmArraySchema._({
    required this.items,
    this.minItems,
    this.maxItems,
    this.description,
  }) : super._();

  /// Item schema.
  final FmSchema items;

  /// Minimum length, when constrained.
  final int? minItems;

  /// Maximum length, when constrained.
  final int? maxItems;

  /// Optional node description.
  final String? description;

  @override
  Map<String, Object?> _toJson({
    required SchemaMode mode,
    required String path,
  }) =>
      {
        'type': 'array',
        'items': items._toJson(mode: mode, path: '$path/items'),
        if (minItems != null) 'minItems': minItems,
        if (maxItems != null) 'maxItems': maxItems,
        if (description != null) 'description': description,
      };
}

/// String node with optional enum (see [FmSchema.string]).
final class FmStringSchema extends FmSchema {
  const FmStringSchema._({this.enumValues, this.description}) : super._();

  /// Allowed values, when constrained. An empty list is invalid upstream
  /// (`empty_enum` sub-case) and rejected locally in output mode.
  final List<String>? enumValues;

  /// Optional node description.
  final String? description;

  @override
  Map<String, Object?> _toJson({
    required SchemaMode mode,
    required String path,
  }) {
    final values = enumValues;
    if (values != null && values.isEmpty && mode == SchemaMode.output) {
      throw UnsupportedSchemaTypeException(
        message: 'Empty string enum at "${path.isEmpty ? '/' : path}" is not '
            'supported (empty_enum).',
        keyword: 'enum',
        path: path.isEmpty ? '/' : path,
        schemaErrorCase: 'empty_enum',
      );
    }
    return {
      'type': 'string',
      if (values != null && values.isNotEmpty) 'enum': values,
      if (description != null) 'description': description,
    };
  }
}

/// Scalar leaf node (`number` / `integer` / `boolean`).
final class FmLeafSchema extends FmSchema {
  const FmLeafSchema._(this.typeName, {this.description}) : super._();

  /// The JSON Schema scalar type name.
  final String typeName;

  /// Optional node description.
  final String? description;

  @override
  Map<String, Object?> _toJson({
    required SchemaMode mode,
    required String path,
  }) =>
      {
        'type': typeName,
        if (description != null) 'description': description,
      };
}

/// Internal `#/\$defs/...` reference (see [FmSchema.ref]).
final class FmRefSchema extends FmSchema {
  FmRefSchema._(this.name) : super._() {
    if (name.contains('://') || name.startsWith('/') || name.contains('..')) {
      throw UnsupportedSchemaTypeException(
        message: 'External \$ref "$name" is not supported; use an internal '
            'definition name with FmSchema.withDefs.',
        keyword: '\$ref',
        path: '/',
        schemaErrorCase: 'external_ref',
      );
    }
  }

  /// Definition name inside `$defs`.
  final String name;

  @override
  Map<String, Object?> _toJson({
    required SchemaMode mode,
    required String path,
  }) =>
      {'\$ref': '#/\$defs/$name'};
}

/// Raw escape-hatch node (see [FmSchema.raw]).
final class FmRawSchema extends FmSchema {
  const FmRawSchema._(this.json) : super._();

  /// The raw JSON-Schema map.
  final Map<String, Object?> json;

  @override
  Map<String, Object?> _toJson({
    required SchemaMode mode,
    required String path,
  }) =>
      FmSchema.validateRaw(json, mode: mode, path: path);
}

/// Root wrapper attaching `$defs` (see [FmSchema.withDefs]).
final class FmDefsSchema extends FmSchema {
  const FmDefsSchema._({required this.defs, required this.root}) : super._();

  /// Named reusable definitions.
  final Map<String, FmSchema> defs;

  /// The root schema.
  final FmSchema root;

  @override
  Map<String, Object?> _toJson({
    required SchemaMode mode,
    required String path,
  }) {
    final rootJson = root._toJson(mode: mode, path: path);
    return {
      ...rootJson,
      '\$defs': defs.map(
        (name, schema) =>
            MapEntry(name, schema._toJson(mode: mode, path: '$path/\$defs/$name')),
      ),
    };
  }
}
