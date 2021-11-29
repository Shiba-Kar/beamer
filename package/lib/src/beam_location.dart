import 'package:beamer/beamer.dart';
import 'package:beamer/src/beam_state.dart';
import 'package:beamer/src/utils.dart';
import 'package:flutter/widgets.dart';

/// Parameters used while beaming.
class BeamParameters {
  /// Creates a [BeamParameters] with specified properties.
  ///
  /// All attributes can be null.
  const BeamParameters({
    this.transitionDelegate = const DefaultTransitionDelegate(),
    this.popConfiguration,
    this.beamBackOnPop = false,
    this.popBeamLocationOnPop = false,
    this.stacked = true,
  });

  /// Which transition delegate to use when building pages.
  final TransitionDelegate transitionDelegate;

  /// Which route to pop to, instead of default pop.
  ///
  /// This is more general than [beamBackOnPop].
  final RouteInformation? popConfiguration;

  /// Whether to implicitly [BeamerDelegate.beamBack] instead of default pop.
  final bool beamBackOnPop;

  /// Whether to remove entire current [BeamLocation] from history,
  /// instead of default pop.
  final bool popBeamLocationOnPop;

  /// Whether all the pages produced by [BeamLocation.buildPages] are stacked.
  /// If not (`false`), just the last page is taken.
  final bool stacked;

  /// Returns a copy of this with optional changes.
  BeamParameters copyWith({
    TransitionDelegate? transitionDelegate,
    RouteInformation? popConfiguration,
    bool? beamBackOnPop,
    bool? popBeamLocationOnPop,
    bool? stacked,
  }) {
    return BeamParameters(
      transitionDelegate: transitionDelegate ?? this.transitionDelegate,
      popConfiguration: popConfiguration ?? this.popConfiguration,
      beamBackOnPop: beamBackOnPop ?? this.beamBackOnPop,
      popBeamLocationOnPop: popBeamLocationOnPop ?? this.popBeamLocationOnPop,
      stacked: stacked ?? this.stacked,
    );
  }
}

/// An element of [BeamLocation.history] list.
///
/// Contains the [RouteInformation] and [BeamParameters] at the moment
/// of beaming to it.
class HistoryElement {
  /// Creates a [HistoryElement] with specified properties.
  ///
  /// [routeInformation] must not be null.
  const HistoryElement(
    this.routeInformation, [
    this.parameters = const BeamParameters(),
  ]);

  /// A [RouteInformation] of this history entry.
  final RouteInformation routeInformation;

  /// Parameters that were used during beaming.
  final BeamParameters parameters;
}

/// Configuration for a navigatable application region.
///
/// Responsible for
///   * knowing which URIs it can handle: [pathPatterns]
///   * knowing how to build a stack of pages: [buildPages]
///   * keeping a [state] that provides the link between the first 2
///
/// Extend this class to define your locations to which you can then beam to.
abstract class BeamLocation<T extends RouteInformationSerializable>
    extends ChangeNotifier {
  /// Creates a [BeamLocation] with specified properties.
  ///
  /// All attributes can be null.
  BeamLocation([
    RouteInformation? routeInformation,
    BeamParameters? beamParameters,
  ]) {
    create(routeInformation, beamParameters);
  }

  /// A state of this [BeamLocation].
  ///
  /// Upon beaming, it will be populated by all necessary attributes.
  /// See also: [BeamState].
  late T state;

  /// Beam parameters used to beam to the current [state].
  BeamParameters get beamParameters => history.last.parameters;

  /// An arbitrary data to be stored in this.
  /// This will persist while navigating within this [BeamLocation].
  ///
  /// Therefore, in the case of using [RoutesLocationBuilder] which uses only
  /// a single [RoutesBeamLocation] for all page stacks, this data will
  /// be available always, until overriden with some new data.
  Object? data;

  /// Whether [buildInit] was called.
  ///
  /// See [buildInit].
  bool mounted = false;

  /// Whether this [BeamLocation] is currently in use by [BeamerDelegate].
  ///
  /// This influences on the behavior of [create] that gets called on existing
  /// [BeamLocation]s when using [BeamerLocationBuilder] that uses [Utils.chooseBeamLocation].
  bool isCurrent = false;

  /// Creates the [state] and adds the [routeInformation] to [history].
  /// This is called only once during the lifetime of [BeamLocation].
  ///
  /// See [createState] and [addToHistory].
  void create([
    RouteInformation? routeInformation,
    BeamParameters? beamParameters,
    bool tryPoppingHistory = true,
  ]) {
    if (!isCurrent) {
      try {
        disposeState();
      } catch (e) {
        //
      }
      history.clear();
    }
    state = createState(
      routeInformation ?? const RouteInformation(location: '/'),
    );
    addToHistory(
      state.routeInformation,
      beamParameters ?? const BeamParameters(),
      tryPoppingHistory,
    );
  }

  /// How to create state from [RouteInformation] given by
  /// [BeamerDelegate] and passed via [BeamerDelegate.locationBuilder].
  ///
  /// This will be called only once during the lifetime of [BeamLocation].
  /// One should override this if using a custom state class.
  ///
  /// See [create].
  T createState(RouteInformation routeInformation) =>
      BeamState.fromRouteInformation(
        routeInformation,
        beamLocation: this,
      ) as T;

  /// What to do on state initalization.
  ///
  /// For example, add listeners to [state] if it's a [ChangeNotifier].
  void initState() {}

  /// Updates the [state] upon recieving new [RouteInformation], which usually
  /// happens after [BeamerDelegate.setNewRoutePath].
  ///
  /// Override this if you are using custom state whose copying
  /// should be handled customly.
  ///
  /// See [update].
  void updateState(RouteInformation routeInformation) {
    state = createState(routeInformation);
  }

  /// How to relase any resources used by [state].
  ///
  /// Override this if
  /// e.g. using a custom [ChangeNotifier] [state] to remove listeners.
  void disposeState() {}

  /// Updates the [state] and [history], depending on inputs.
  ///
  /// If [copy] function is provided, state should be created from given current [state].
  /// New [routeInformation] gets added to history.
  ///
  /// If [copy] is `null`, then [routeInformation] is used, either `null` or not.
  /// If [routeInformation] is `null`, then the state will upadate from
  /// last [history] element and nothing shall be added to [history].
  /// Else, the state updates from available [routeInformation].
  ///
  /// See [updateState] and [addToHistory].
  void update([
    T Function(T)? copy,
    RouteInformation? routeInformation,
    BeamParameters? beamParameters,
    bool rebuild = true,
    bool tryPoppingHistory = true,
  ]) {
    if (copy != null) {
      state = copy(state);
      addToHistory(
        state.routeInformation,
        beamParameters ?? const BeamParameters(),
        tryPoppingHistory,
      );
    } else {
      if (routeInformation == null) {
        updateState(history.last.routeInformation);
      } else {
        updateState(routeInformation);
        addToHistory(
          state.routeInformation,
          beamParameters ?? const BeamParameters(),
          tryPoppingHistory,
        );
      }
    }
    if (rebuild) {
      notifyListeners();
    }
  }

  /// The history of beaming for this.
  List<HistoryElement> history = [];

  /// Adds another [HistoryElement] to [history] list.
  /// The history element is created from given [state] and [beamParameters].
  ///
  /// If [tryPopping] is set to `true`, the state with the same `location`
  /// will be searched in [history] and if found, entire history segment
  /// `[foundIndex, history.length-1]` will be removed before adding a new
  /// history element.
  void addToHistory(
    RouteInformation routeInformation, [
    BeamParameters beamParameters = const BeamParameters(),
    bool tryPopping = true,
  ]) {
    if (tryPopping) {
      final sameStateIndex = history.indexWhere((element) {
        return element.routeInformation.location ==
            state.routeInformation.location;
      });
      if (sameStateIndex != -1) {
        history.removeRange(sameStateIndex, history.length);
      }
    }
    if (history.isEmpty ||
        routeInformation.location != history.last.routeInformation.location) {
      history.add(HistoryElement(routeInformation, beamParameters));
    }
  }

  /// Removes the last [HistoryElement] from [history] and returns it.
  ///
  /// If said history element is a `ChangeNotifier`, listeners are removed.
  HistoryElement? removeLastFromHistory() {
    if (history.isEmpty) {
      return null;
    }
    return history.removeLast();
  }

  /// Initialize custom bindings for this [BeamLocation] using [BuildContext].
  /// Similar to [builder], but is not tied to Widget tree.
  ///
  /// This will be called on just the first build of this [BeamLocation]
  /// and sets [mounted] to true. It is called right before [buildPages].
  @mustCallSuper
  void buildInit(BuildContext context) {
    mounted = true;
  }

  /// Can this handle the [uri] based on its [pathPatterns].
  ///
  /// Can be useful in a custom [BeamerDelegate.locationBuilder].
  bool canHandle(Uri uri) => Utils.canBeamLocationHandleUri(this, uri);

  /// Gives the ability to wrap the [navigator].
  ///
  /// Mostly useful for providing something to the entire location,
  /// i.e. to all of the pages.
  ///
  /// For example:
  ///
  /// ```dart
  /// @override
  /// Widget builder(BuildContext context, Widget navigator) {
  ///   return MyProvider<MyObject>(
  ///     create: (context) => MyObject(),
  ///     child: navigator,
  ///   );
  /// }
  /// ```
  Widget builder(BuildContext context, Widget navigator) => navigator;

  /// Represents the "form" of URI paths supported by this [BeamLocation].
  ///
  /// You can pass in either a String or a RegExp. Beware of using greedy regular
  /// expressions as this might lead to unexpected behaviour.
  ///
  /// For strings, optional path segments are denoted with ':xxx' and consequently
  /// `{'xxx': <real>}` will be put to [pathParameters].
  /// For regular expressions we use named groups as optional path segments, following
  /// regex is tested to be effective in most cases `RegExp('/test/(?<test>[a-z]+){0,1}')`
  /// This will put `{'test': <real>}` to [pathParameters]. Note that we use the name from the regex group.
  ///
  /// Optional path segments can be used as a mean to pass data regardless of
  /// whether there is a browser.
  ///
  /// For example: '/books/:id' or using regex `RegExp('/test/(?<test>[a-z]+){0,1}')`
  List<Pattern> get pathPatterns;

  /// Creates and returns the list of pages to be built by the [Navigator]
  /// when this [BeamLocation] is beamed to or internally inferred.
  ///
  /// [context] can be useful while building the pages.
  /// It will also contain anything injected via [builder].
  List<BeamPage> buildPages(BuildContext context, T state);

  /// Guards that will be executing [check] when this gets beamed to.
  ///
  /// Checks will be executed in order; chain of responsibility pattern.
  /// When some guard returns `false`, a candidate will not be accepted
  /// and stack of pages will be updated as is configured in [BeamGuard].
  ///
  /// Override this in your subclasses, if needed.
  /// See [BeamGuard].
  List<BeamGuard> get guards => const <BeamGuard>[];

  /// A transition delegate to be used by [Navigator].
  ///
  /// This will be used only by this location, unlike
  /// [BeamerDelegate.transitionDelegate] that will be used for all locations.
  ///
  /// This transition delegate will override the one in [BeamerDelegate].
  ///
  /// See [Navigator.transitionDelegate].
  TransitionDelegate? get transitionDelegate => null;
}

/// Default location to choose if requested URI doesn't parse to any location.
class NotFound extends BeamLocation<BeamState> {
  /// Creates a [NotFound] [BeamLocation] with
  /// `RouteInformation(location: path)` as its state.
  NotFound({String path = '/'}) : super(RouteInformation(location: path));

  @override
  List<BeamPage> buildPages(BuildContext context, BeamState state) => [];

  @override
  List<String> get pathPatterns => [];
}

/// Empty location used to intialize a non-nullable BeamLocation variable.
///
/// See [BeamerDelegate.currentBeamLocation].
class EmptyBeamLocation extends BeamLocation<BeamState> {
  @override
  List<BeamPage> buildPages(BuildContext context, BeamState state) => [];

  @override
  List<String> get pathPatterns => [];
}

/// A beam location for [RoutesLocationBuilder], but can be used freely.
///
/// Useful when needing a simple beam location with a single or few pages.
class RoutesBeamLocation extends BeamLocation<BeamState> {
  /// Creates a [RoutesBeamLocation] with specified properties.
  ///
  /// [routeInformation] and [routes] are required.
  RoutesBeamLocation({
    required RouteInformation routeInformation,
    Object? data,
    BeamParameters? beamParameters,
    required this.routes,
    this.navBuilder,
  }) : super(routeInformation, beamParameters);

  /// Map of all routes this location handles.
  Map<Pattern, dynamic Function(BuildContext, BeamState)> routes;

  /// A wrapper used as [BeamLocation.builder].
  Widget Function(BuildContext context, Widget navigator)? navBuilder;

  @override
  Widget builder(BuildContext context, Widget navigator) {
    return navBuilder?.call(context, navigator) ?? navigator;
  }

  int _compareKeys(Pattern a, Pattern b) {
    if (a is RegExp && b is RegExp) {
      return a.pattern.length - b.pattern.length;
    }
    if (a is RegExp && b is String) {
      return a.pattern.length - b.length;
    }
    if (a is String && b is RegExp) {
      return a.length - b.pattern.length;
    }
    if (a is String && b is String) {
      return a.length - b.length;
    }
    return 0;
  }

  @override
  List<Pattern> get pathPatterns => routes.keys.toList();

  @override
  List<BeamPage> buildPages(BuildContext context, BeamState state) {
    final filteredRoutes = chooseRoutes(state.routeInformation, routes.keys);
    final routeBuilders = Map.of(routes)
      ..removeWhere((key, value) => !filteredRoutes.containsKey(key));
    final sortedRoutes = routeBuilders.keys.toList()
      ..sort((a, b) => _compareKeys(a, b));
    final pages = sortedRoutes.map<BeamPage>((route) {
      final routeElement = routes[route]!(context, state);
      if (routeElement is BeamPage) {
        return routeElement;
      } else {
        return BeamPage(
          key: ValueKey(filteredRoutes[route]),
          child: routeElement,
        );
      }
    }).toList();
    return pages;
  }

  /// Chooses all the routes that "sub-match" [state.routeInformation] to stack their pages.
  ///
  /// If none of the routes _matches_ [state.uri], nothing will be selected
  /// and [BeamerDelegate] will declare that the location is [NotFound].
  static Map<Pattern, String> chooseRoutes(
    RouteInformation routeInformation,
    Iterable<Pattern> routes,
  ) {
    final matched = <Pattern, String>{};
    bool overrideNotFound = false;
    final uri = Uri.parse(routeInformation.location ?? '/');
    for (final route in routes) {
      if (route is String) {
        final uriPathSegments = uri.pathSegments.toList();
        final routePathSegments = Uri.parse(route).pathSegments;

        if (uriPathSegments.length < routePathSegments.length) {
          continue;
        }

        var checksPassed = true;
        var path = '';
        for (int i = 0; i < routePathSegments.length; i++) {
          path += '/${uriPathSegments[i]}';

          if (routePathSegments[i] == '*') {
            overrideNotFound = true;
            continue;
          }
          if (routePathSegments[i].startsWith(':')) {
            continue;
          }
          if (routePathSegments[i] != uriPathSegments[i]) {
            checksPassed = false;
            break;
          }
        }

        if (checksPassed) {
          matched[route] = Uri(
            path: path == '' ? '/' : path,
            queryParameters:
                uri.queryParameters.isEmpty ? null : uri.queryParameters,
          ).toString();
        }
      } else {
        final regexp = Utils.tryCastToRegExp(route);
        if (regexp.hasMatch(uri.toString())) {
          final path = uri.toString();
          matched[regexp] = Uri(
            path: path == '' ? '/' : path,
            queryParameters:
                uri.queryParameters.isEmpty ? null : uri.queryParameters,
          ).toString();
        }
      }
    }

    bool isNotFound = true;
    matched.forEach((key, value) {
      if (Utils.urisMatch(key, uri)) {
        isNotFound = false;
      }
    });

    if (overrideNotFound) {
      return matched;
    }

    return isNotFound ? {} : matched;
  }
}
