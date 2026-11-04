import 'package:artemis/builder.dart';
import 'package:artemis/generator/data/data.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:collection/collection.dart';

/// Runs [testBuilder] and rethrows the first error the builder raised.
///
/// Since build_test 3, `testBuilder` logs a builder's exception (as text)
/// and returns a failed result instead of throwing it, so the builder is
/// wrapped to keep the original exception object.
Future<TestBuilderResult> testBuilderRethrowing(
  Builder builder,
  Map<String, Object> sourceAssets, {
  Map<String, Object>? outputs,
}) async {
  final capturing = _ErrorCapturingBuilder(builder);
  final result = await testBuilder(
    capturing,
    sourceAssets,
    outputs: outputs,
    onLog: print,
  );
  final error = capturing.error;
  if (error != null) throw error;
  return result;
}

class _ErrorCapturingBuilder implements Builder {
  _ErrorCapturingBuilder(this._inner);

  final Builder _inner;
  Object? error;

  @override
  Map<String, List<String>> get buildExtensions => _inner.buildExtensions;

  @override
  Future<void> build(BuildStep buildStep) async {
    try {
      await _inner.build(buildStep);
    } catch (e) {
      error ??= e;
      rethrow;
    }
  }
}

/// Matches Dart source ignoring layout: whitespace and trailing commas.
///
/// The generator formats its output with `dart_style`, whose layout changes
/// between major versions (e.g. the "tall" style of 3.x). These tests check
/// what is generated, not how the formatter lays it out.
Matcher equalsDartCode(String expected) => _DartCodeMatcher(expected);

String _normalizeDartCode(String code) => code
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAllMapped(RegExp(r',([)\]}])'), (m) => m[1]!);

class _DartCodeMatcher extends CustomMatcher {
  _DartCodeMatcher(String expected)
      : super('Dart code equal (ignoring layout) to', 'normalized code',
            _normalizeDartCode(expected));

  @override
  Object? featureValueOf(dynamic actual) =>
      _normalizeDartCode(actual as String);
}

final bool Function(Iterable, Iterable) listEquals =
    const DeepCollectionEquality.unordered().equals;

Future testGenerator({
  required String query,
  required LibraryDefinition libraryDefinition,
  required String generatedFile,
  required String schema,
  String namingScheme = 'pathedWithTypes',
  bool appendTypeName = false,
  bool generateHelpers = false,
  bool generateQueries = false,
  Map<String, dynamic> builderOptionsMap = const {},
  Map<String, Object> sourceAssetsMap = const {},
  Map<String, Object> outputsMap = const {},
}) async {
  Logger.root.level = Level.INFO;

  final anotherBuilder = graphQLQueryBuilder(BuilderOptions({
    if (!generateHelpers) 'generate_helpers': false,
    if (!generateQueries) 'generate_queries': false,
    'schema_mapping': [
      {
        'schema': 'api.schema.graphql',
        'queries_glob': 'queries/**.graphql',
        'output': 'lib/query.graphql.dart',
        'naming_scheme': namingScheme,
        'append_type_name': appendTypeName,
      }
    ],
    ...builderOptionsMap,
  }));

  anotherBuilder.onBuild = expectAsync1((definition) {
    log.fine(definition);
    expect(definition, libraryDefinition);
  }, count: 1);

  return await testBuilder(
    anotherBuilder,
    {
      'a|api.schema.graphql': schema,
      'a|queries/query.graphql': query,
      ...sourceAssetsMap,
    },
    outputs: {
      'a|lib/query.graphql.dart': decodedMatches(equalsDartCode(generatedFile)),
      ...outputsMap,
    },
    onLog: print,
  );
}

Future testNaming({
  required String query,
  required String schema,
  required List<String> expectedNames,
  required String namingScheme,
  bool shouldFail = false,
}) {
  final anotherBuilder = graphQLQueryBuilder(BuilderOptions({
    'generate_helpers': false,
    'generate_queries': false,
    'schema_mapping': [
      {
        'schema': 'api.schema.graphql',
        'queries_glob': 'queries/**.graphql',
        'output': 'lib/query.dart',
        'naming_scheme': namingScheme,
      }
    ],
  }));

  if (!shouldFail) {
    anotherBuilder.onBuild = expectAsync1((definition) {
      final names = definition.queries.first.classes
          .map((e) => e.name.namePrintable)
          .toSet();
      log.fine(names);
      expect(names.toSet(), equals(expectedNames.toSet()));
    }, count: 1);
  }

  return testBuilder(
    anotherBuilder,
    {
      'a|api.schema.graphql': schema,
      'a|queries/query.graphql': query,
    },
    onLog: print,
  );
}
