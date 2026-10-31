import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import 'models/gamification_profile.dart';
import 'models/exploration_session.dart';
import 'models/zoo_waypoint.dart';
import 'screens/animal_discovery_card_screen.dart';
import 'screens/animal_directory_screen.dart';
import 'screens/wildlife_collection_screen.dart';
import 'screens/zoo_home_screen.dart';
import 'services/animal_information_service.dart';
import 'services/exploration_planner.dart';
import 'services/gamification_service.dart';
import 'services/gamification_storage_service.dart';
import 'widgets/animal_discovery_action.dart';
import 'widgets/exploration_session_panel.dart';

export 'models/zoo_waypoint.dart';

void main() {
  runApp(const ZooMapApp());
}

class ZooMapApp extends StatefulWidget {
  const ZooMapApp({super.key, this.startIn3dMode = true});

  final bool startIn3dMode;

  @override
  State<ZooMapApp> createState() => _ZooMapAppState();
}

class _ZooMapAppState extends State<ZooMapApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dehiwala Zoo Explorer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF286A45),
          surface: const Color(0xFFFFFCF5),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F3EA),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF76C893),
          brightness: Brightness.dark,
          surface: const Color(0xFF1C2922),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF111A15),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF1C2922),
          indicatorColor: Color(0xFF315A3D),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1C2922),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      themeMode: _themeMode,
      home: ZooMapScreen(
        startIn3dMode: widget.startIn3dMode,
        isDarkMode: _themeMode == ThemeMode.dark,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

class ZooMapScreen extends StatefulWidget {
  const ZooMapScreen({
    super.key,
    this.startIn3dMode = true,
    this.isDarkMode = false,
    this.onToggleTheme,
  });

  final bool startIn3dMode;
  final bool isDarkMode;
  final VoidCallback? onToggleTheme;

  @override
  State<ZooMapScreen> createState() => _ZooMapScreenState();
}

class _ZooMapScreenState extends State<ZooMapScreen> {
  late final Future<ZooMapData> _mapDataFuture;

  // Controls the position and zoom of the map.
  final MapController _mapController = MapController();
  final ValueNotifier<double> _flutterMapZoom = ValueNotifier<double>(17);
  final ValueNotifier<double> _mapCompassBearing = ValueNotifier<double>(20);

  // Stores the visitor's most recently retrieved position.
  LatLng? _currentPosition;
  double? _visitorHeadingDegrees;

  // Prevents repeated location requests while one is running.
  bool _isLocating = false;
  bool _isSearchExpanded = false;
  int _selectedTab = 0;
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<List<ZooWaypoint>> _visibleWaypoints =
      ValueNotifier<List<ZooWaypoint>>([]);
  List<ZooWaypoint> _allWaypoints = const [];
  final Map<int, Future<ui.Image>> _cartoonAtlasCache = {};
  late final GamificationService _gamificationService;
  StreamSubscription<Position>? _positionSubscription;
  ExplorationSession? _explorationSession;
  bool _isExplorationPanelMinimized = false;
  bool _isLiveLocationTracking = false;
  final AnimalInformationService _animalInformationService =
      AnimalInformationService();
  GamificationProfile _gamificationProfile = GamificationProfile.empty();
  bool _gamificationReady = false;
  String? _gamificationLoadError;
  String _selectedCategory = 'Animals';
  late final bool _is3dMode;
  bool _isMap3dView = true;
  maplibre.MapLibreMapController? _mapLibreController;
  bool _mapLibreStyleReady = false;
  LatLng? _pendingMapTarget;
  double _pendingMapZoom = 17;
  ZooMapExtent? _zooMapExtent;
  ZooMapExtent? _zooVisitExtent;

  static const _mapLibreStyle = 'https://tiles.openfreemap.org/styles/liberty';
  static const _darkMapLibreStyle = 'https://tiles.openfreemap.org/styles/dark';
  static const _categories = ['All', 'Animals', 'Facilities', 'Landmarks'];
  static const _darkTileColorFilter = ColorFilter.matrix([
    -0.2,
    -0.2,
    -0.2,
    0,
    125,
    -0.2,
    -0.2,
    -0.2,
    0,
    138,
    -0.2,
    -0.2,
    -0.2,
    0,
    150,
    0,
    0,
    0,
    1,
    0,
  ]);
  static const _waypointSourceId = 'zoo-waypoints';
  static const _routeSourceId = 'zoo-routes';
  static const _visitorSourceId = 'visitor-location';
  static const _facilityPinImageId = 'zoo-facility-pin';
  static const _landmarkPinImageId = 'zoo-landmark-pin';

  String _enclosureImageId(ZooWaypoint waypoint) =>
      'zoo-enclosure-${waypoint.id}';

  static const _cartoonFrames = <String, int>{
    'ostrich': 0,
    'crowned crane': 1,
    'cassowary': 2,
    'black swan': 3,
    'oryx / gaur': 4,
    'blue-and-yellow macaw / scarlet macaw': 5,
    'camel': 7,
    'brown bear': 8,
    'fox': 9,
    'bengal tiger': 10,
    'eurasian otter': 11,
    'meerkat': 12,
    'jungle cat': 13,
    'ring-tailed lemur': 14,
    'purple-faced langur': 15,
    'grey langur': 16,
    'white toque monkey': 17,
    'hippopotamus': 18,
    'capybara': 19,
    'elephant': 20,
    'deer': 21,
    'nilgai / hog deer / muntjac': 22,
    'hamadryas baboon': 25,
    'lion': 26,
    'african lion': 27,
    'chimpanzee': 28,
    'mule': 29,
    'brahminy kite / mountain hawk-eagle': 30,
    'white-bellied sea eagle': 32,
    'emu': 33,
    "bennett's wallaby": 34,
    'wild boar': 35,
    'lechwe': 36,
    'scimitar-horned oryx': 37,
    'rhinoceros': 38,
    'sheep': 39,
    'greater kudu': 40,
    'wild horse': 41,
    'horse': 42,
    'donkey': 43,
    'swan': 44,
    'sloth bear': 45,
    'black jaguar / jaguar': 46,
    'llama': 47,
  };

  String _animalGroup(String name) {
    final species = name
        .replaceFirst(RegExp(r'\s+\d+$'), '')
        .split('/')
        .first
        .trim();
    const birds = {
      'Ostrich',
      'Crowned Crane',
      'Cassowary',
      'Black Swan',
      'Blue-and-yellow Macaw',
      'Brahminy Kite',
      'White-bellied Sea Eagle',
      'Emu',
      'Swan',
    };
    return birds.contains(species) ? 'Birds' : 'Mammals';
  }

  @override
  void initState() {
    super.initState();
    _is3dMode = widget.startIn3dMode && _supports3dMap;
    _gamificationService = GamificationService(
      storage: const FileGamificationStorageService(),
      locationProvider: const GeolocatorDiscoveryLocationProvider(),
    );
    unawaited(_loadGamification());
    _mapDataFuture = _loadMapData();
    _searchController.addListener(_onSearchChanged);
    _visibleWaypoints.addListener(_onVisibleWaypointsChanged);
  }

  Future<void> _loadGamification() async {
    try {
      await _gamificationService.load();
      if (!mounted) return;
      setState(() {
        _gamificationProfile = _gamificationService.profile;
        _gamificationReady = true;
      });
      _updateFilteredWaypoints();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _gamificationLoadError = error.toString();
      });
    }
  }

  List<ZooWaypoint> _eligibleAnimals(Iterable<ZooWaypoint> waypoints) =>
      waypoints.where(_gamificationService.rules.isEligible).toList();

  ExplorationDestination? _nextExplorationDestination(
    Iterable<ZooWaypoint> waypoints,
  ) => ExplorationPlanner.nextEligibleAnimal(
    waypoints: waypoints,
    profile: _gamificationProfile,
    rules: _gamificationService.rules,
    currentLocation: _currentPosition,
  );

  int _discoveredEligibleCount(Iterable<ZooWaypoint> animals) => animals
      .where((animal) => _gamificationProfile.hasDiscovered(animal.id))
      .length;

  void _handleDiscoveryResult(ZooWaypoint waypoint, DiscoveryResult result) {
    if (!mounted) return;
    if (result.wasDiscovered) {
      setState(() {
        _gamificationProfile = result.profile;
        final session = _explorationSession;
        if (session != null) {
          _explorationSession = session.recordDiscovery(
            waypoint.id,
            result.xpAwarded,
          );
        }
      });
      _updateFilteredWaypoints();
      _openAnimalCard(waypoint, showReward: true);
    } else {
      _showMessage(_discoveryMessage(result));
    }
  }

  Future<void> _startExploration() async {
    if (_explorationSession != null) return;
    FocusScope.of(context).unfocus();
    _searchController.clear();
    setState(() {
      _explorationSession = ExplorationSession.start(DateTime.now());
      _isExplorationPanelMinimized = false;
      _currentPosition = null;
      _selectedTab = 1;
      _selectedCategory = 'Animals';
      _isSearchExpanded = false;
    });
    _updateFilteredWaypoints();
    _showMessage('Your wildlife adventure has started. Happy exploring!');

    await _locateMe(followUser: false);
    if (!mounted || _explorationSession == null) return;
    await _ensurePositionStream();
  }

  Future<void> _ensurePositionStream() async {
    if (_positionSubscription != null) return;
    if (_explorationSession == null && !_isLiveLocationTracking) return;

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (_isLiveLocationTracking && mounted) {
          setState(() => _isLiveLocationTracking = false);
          _showMessage('Location service is off. Turn it on to keep tracking.');
        }
        return;
      }
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        if (_isLiveLocationTracking && mounted) {
          setState(() => _isLiveLocationTracking = false);
          _showMessage('Location permission is needed to keep tracking.');
        }
        return;
      }

      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen(
            (position) {
              if (!mounted) return;
              final point = LatLng(position.latitude, position.longitude);
              _setVisitorPosition(
                point,
                focusMap: _isLiveLocationTracking && _isInsideZooArea(point),
                headingDegrees: _headingFromPosition(position),
              );
            },
            onError: (Object error) {
              debugPrint('Live location updates stopped: $error');
              _positionSubscription = null;
              if (mounted) {
                setState(() => _isLiveLocationTracking = false);
                _showMessage(
                  'Live location updates stopped. Tap Locate Me to resume.',
                );
              }
            },
          );
    } catch (error) {
      debugPrint('Could not start live location updates: $error');
      if (_isLiveLocationTracking && mounted) {
        setState(() => _isLiveLocationTracking = false);
        _showMessage('Could not start tracking. Check your location settings.');
      }
    }
  }

  double? _headingFromPosition(Position position) {
    if (!position.hasHeading || position.speed < 0.5) return null;
    if (position.hasHeadingAccuracy && position.headingAccuracy > 45) {
      return null;
    }
    return position.heading;
  }

  Future<void> _handleLocateMePressed() async {
    if (_isLocating) return;
    if (_isLiveLocationTracking) {
      setState(() => _isLiveLocationTracking = false);
      if (_explorationSession == null) {
        await _positionSubscription?.cancel();
        _positionSubscription = null;
        _showMessage('Live location tracking paused.');
      } else {
        _showMessage(
          'Map follow paused. Exploration location updates continue.',
        );
      }
      return;
    }
    await _locateMe();
  }

  Future<void> _finishExploration() async {
    final session = _explorationSession;
    if (session == null) return;
    if (!mounted) return;
    setState(() => _explorationSession = null);
    if (!_isLiveLocationTracking) {
      await _positionSubscription?.cancel();
      _positionSubscription = null;
    }
    _updateFilteredWaypoints();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          icon: Icon(
            Icons.celebration_rounded,
            color: colors.tertiary,
            size: 38,
          ),
          title: const Text('Adventure complete!'),
          content: Text(
            session.discoveryCount == 0
                ? 'Keep exploring to discover animal friends and earn XP.'
                : 'You discovered ${session.discoveryCount} new '
                      '${session.discoveryCount == 1 ? 'animal' : 'animals'} '
                      'and earned ${session.xpEarned} XP this trip.',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Finish'),
            ),
          ],
        );
      },
    );
  }

  void _setVisitorPosition(
    LatLng point, {
    required bool focusMap,
    double? headingDegrees,
  }) {
    if (!mounted) return;
    setState(() {
      _currentPosition = point;
      if (headingDegrees != null && headingDegrees.isFinite) {
        _visitorHeadingDegrees = headingDegrees % 360;
      }
    });
    _updateFilteredWaypoints();
    final controller = _mapLibreController;
    if (_is3dMode && controller != null && _mapLibreStyleReady) {
      unawaited(
        controller
            .setGeoJsonSource(
              _visitorSourceId,
              _visitorGeoJson(point, heading: _visitorHeadingDegrees),
            )
            .catchError((Object error) {
              debugPrint('Could not update visitor location: $error');
            }),
      );
    }
    if (focusMap) _moveMapTo(point, 18);
  }

  Widget _buildVisitorLocationMarker() {
    final heading = _visitorHeadingDegrees;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (heading != null)
            Transform.rotate(
              angle: heading * math.pi / 180,
              child: const CustomPaint(
                size: Size(48, 48),
                painter: _VisitorHeadingPainter(),
              ),
            ),
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFF2878D0),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openAnimalCard(ZooWaypoint waypoint, {bool showReward = false}) {
    final discovery = _gamificationProfile.discoveries[waypoint.id];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AnimalDiscoveryCardScreen(
          animal: waypoint,
          discovery: discovery,
          profile: _animalInformationService.profileFor(waypoint.id),
          informationService: _animalInformationService,
          showReward: showReward,
          onShowOnMap: () => _focusAnimalOnMap(waypoint),
        ),
      ),
    );
  }

  void _focusAnimalOnMap(ZooWaypoint waypoint) {
    FocusScope.of(context).unfocus();
    _selectedCategory = mapCategoryForWaypoint(waypoint.category);
    _searchController.clear();
    _updateFilteredWaypoints();
    setState(() {
      _selectedTab = 1;
      _isSearchExpanded = false;
    });
    _moveMapTo(LatLng(waypoint.latitude, waypoint.longitude), 18);
  }

  String _discoveryMessage(DiscoveryResult result) {
    return switch (result.status) {
      DiscoveryStatus.alreadyDiscovered =>
        'You have already discovered this animal location.',
      DiscoveryStatus.notEligible =>
        'This location is not eligible for animal discovery XP.',
      DiscoveryStatus.serviceDisabled =>
        'Turn on Location Services and try again.',
      DiscoveryStatus.permissionDenied =>
        'Location permission was denied. Allow it and try again.',
      DiscoveryStatus.permissionDeniedForever =>
        'Location permission is blocked. Enable it in app settings.',
      DiscoveryStatus.timedOut =>
        'GPS took too long to respond. Move to an open area and try again.',
      DiscoveryStatus.locationUnavailable =>
        'Could not get your location. Check GPS and try again.',
      DiscoveryStatus.poorAccuracy =>
        'GPS accuracy is too low. Move to an open area and try again.',
      DiscoveryStatus.tooFar =>
        'You are about ${result.distanceMeters?.round() ?? 0} m away. '
            'Get within ${_gamificationService.rules.proximityRadiusMeters.round()} m and try again.',
      DiscoveryStatus.storageError =>
        'Progress could not be saved. Check device storage and try again.',
      DiscoveryStatus.debugOnlyUnavailable =>
        'Discovery simulation is available only in debug builds.',
      DiscoveryStatus.discovered => 'Discovery saved.',
    };
  }

  @override
  void dispose() {
    unawaited(_positionSubscription?.cancel());
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    _visibleWaypoints.removeListener(_onVisibleWaypointsChanged);
    _visibleWaypoints.dispose();
    _flutterMapZoom.dispose();
    _mapCompassBearing.dispose();
    for (final atlas in _cartoonAtlasCache.values) {
      unawaited(atlas.then((image) => image.dispose()));
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ZooMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDarkMode != widget.isDarkMode && _is3dMode) {
      _mapLibreStyleReady = false;
    }
  }

  bool get _supports3dMap =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  ZooMapExtent _boundsFor(ZooMapData data) {
    var south = 90.0;
    var north = -90.0;
    var west = 180.0;
    var east = -180.0;

    void include(LatLng point) {
      if (point.latitude < south) south = point.latitude;
      if (point.latitude > north) north = point.latitude;
      if (point.longitude < west) west = point.longitude;
      if (point.longitude > east) east = point.longitude;
    }

    for (final waypoint in data.waypoints) {
      include(LatLng(waypoint.latitude, waypoint.longitude));
    }
    for (final route in data.routes) {
      for (final point in route) {
        include(point);
      }
    }

    _zooVisitExtent = (south: south, west: west, north: north, east: east);

    final latitudePadding = (north - south) * 0.15;
    final longitudePadding = (east - west) * 0.12;
    return (
      south: south - latitudePadding,
      west: west - longitudePadding,
      north: north + latitudePadding,
      east: east + longitudePadding,
    );
  }

  void _onSearchChanged() {
    _updateFilteredWaypoints();
  }

  void _updateFilteredWaypoints() {
    if (_allWaypoints.isNotEmpty) {
      _visibleWaypoints.value = _filterWaypoints(_allWaypoints);
    }
  }

  void _onVisibleWaypointsChanged() {
    final controller = _mapLibreController;
    if (controller == null || !_mapLibreStyleReady) return;
    unawaited(
      controller
          .setGeoJsonSource(
            _waypointSourceId,
            _waypointsGeoJson(_visibleWaypoints.value),
          )
          .catchError((Object error) {
            debugPrint('Could not update 3D map locations: $error');
          }),
    );
  }

  List<ZooWaypoint> _filterWaypoints(List<ZooWaypoint> waypoints) {
    final query = _searchController.text.trim().toLowerCase();
    return filterZooWaypoints(
      waypoints,
      category: _selectedCategory,
      query: query,
    );
  }

  void _selectWaypoint(ZooWaypoint waypoint) {
    FocusScope.of(context).unfocus();
    _selectedCategory = mapCategoryForWaypoint(waypoint.category);
    _searchController.clear();
    _updateFilteredWaypoints();
    setState(() {
      _isSearchExpanded = false;
    });
    _moveMapTo(LatLng(waypoint.latitude, waypoint.longitude), 18);
    _showWaypointDetails(waypoint);
  }

  void _openWaypointFromDirectory(ZooWaypoint waypoint) {
    FocusScope.of(context).unfocus();
    _selectedCategory = mapCategoryForWaypoint(waypoint.category);
    _searchController.clear();
    _updateFilteredWaypoints();
    setState(() {
      _selectedTab = 1;
      _isSearchExpanded = false;
    });
    _moveMapTo(LatLng(waypoint.latitude, waypoint.longitude), 18);
    _showWaypointDetails(waypoint);
  }

  void _selectTab(int index) {
    FocusScope.of(context).unfocus();
    if (index != 1) {
      _selectedCategory = 'All';
      _searchController.clear();
      _isSearchExpanded = false;
    }
    setState(() => _selectedTab = index);
  }

  Widget _buildDirectory(ZooMapData data, String category) {
    final allLocations =
        data.waypoints
            .where((waypoint) => waypoint.category.toLowerCase() == category)
            .toList()
          ..sort((first, second) => first.name.compareTo(second.name));
    final locations = allLocations;
    if (category == 'animal') {
      return _buildAnimalDirectory(locations);
    }

    final colors = Theme.of(context).colorScheme;

    final categoryLabel = switch (category) {
      'facility' => 'Facilities',
      'landmark' => 'Landmarks',
      _ => 'Locations',
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    categoryLabel,
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    category == 'landmark'
                        ? 'Points of interest around the zoo'
                        : 'Everything you need for an easy visit',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${locations.length} ${category == 'landmark' ? 'landmarks' : 'places'}',
                style: TextStyle(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            _themeToggleButton(),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          category == 'landmark' ? 'Zoo landmarks' : 'Zoo facilities',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        for (final waypoint in locations)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Card(
              color: colors.surface,
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
                leading: _buildWaypointThumbnail(waypoint),
                title: Text(
                  waypoint.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: _buildWaypointQualityInfo(
                  waypoint,
                  fallback: category == 'landmark'
                      ? 'Zoo landmark'
                      : 'Visitor facility',
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                onTap: () => _openWaypointFromDirectory(waypoint),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAnimalDirectory(List<ZooWaypoint> animals) =>
      AnimalDirectoryScreen(
        animals: animals,
        profile: _gamificationProfile,
        groupForName: _animalGroup,
        onOpenAnimal: _openWaypointFromDirectory,
        onShowOnMap: _focusAnimalOnMap,
        onToggleTheme: widget.onToggleTheme ?? () {},
        isDarkMode: widget.isDarkMode,
      );
  Widget _themeToggleButton() => IconButton.filledTonal(
    tooltip: widget.isDarkMode
        ? 'Switch to light theme'
        : 'Switch to dark theme',
    onPressed: widget.onToggleTheme,
    icon: Icon(
      widget.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
    ),
  );

  Widget _buildMapCompass(ColorScheme colors) => Material(
    color: colors.surface.withValues(alpha: 0.97),
    elevation: 5,
    shadowColor: Colors.black.withValues(alpha: 0.16),
    borderRadius: BorderRadius.circular(16),
    child: ValueListenableBuilder<double>(
      valueListenable: _mapCompassBearing,
      builder: (context, bearing, _) => IconButton(
        tooltip: 'Reset map direction',
        onPressed: _resetMapNorth,
        icon: Transform.rotate(
          angle: -bearing * math.pi / 180,
          child: Icon(
            Icons.navigation_rounded,
            color: colors.primary,
            size: 22,
          ),
        ),
      ),
    ),
  );

  Widget _buildWaypointThumbnail(ZooWaypoint waypoint) {
    if (waypoint.category.toLowerCase() == 'animal') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: _buildAnimalIllustration(waypoint.name, width: 54, height: 54),
      );
    }
    return _waypointIcon(waypoint);
  }

  Widget _waypointIcon(ZooWaypoint waypoint) {
    return CircleAvatar(
      radius: 26,
      backgroundColor: _markerColor(waypoint.category).withValues(alpha: 0.12),
      foregroundColor: _markerColor(waypoint.category),
      child: Icon(_markerIcon(waypoint.category)),
    );
  }

  int _cartoonFrameFor(String animalName) {
    final species = animalName
        .replaceFirst(RegExp(r'\s+\d+$'), '')
        .trim()
        .toLowerCase();
    return _cartoonFrames[species] ?? 0;
  }

  Widget _buildAnimalSpriteCrop(String animalName, {required double size}) {
    final frame = _cartoonFrameFor(animalName);
    final localFrame = frame % 16;
    final asset =
        'assets/images/animals/cartoon_animals_${frame ~/ 16 + 1}.png';
    return ClipRect(
      child: SizedBox(
        width: size,
        height: size,
        child: OverflowBox(
          minWidth: size * 4,
          maxWidth: size * 4,
          minHeight: size * 4,
          maxHeight: size * 4,
          alignment: Alignment(
            -1 + (localFrame % 4) * (2 / 3),
            -1 + (localFrame ~/ 4) * (2 / 3),
          ),
          child: Image.asset(
            asset,
            width: size * 4,
            height: size * 4,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => const Icon(
              Icons.pets_rounded,
              size: 42,
              color: Color(0xFF39734B),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimalIllustration(
    String animalName, {
    required double width,
    required double height,
  }) {
    final spriteSize = math.min(width, height);

    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: AnimalHabitatBackdropPainter(animalName),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: _buildAnimalSpriteCrop(animalName, size: spriteSize)),
            Positioned(
              top: 10,
              right: 10,
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.9),
                shadows: const [
                  Shadow(color: Color(0x44344B35), blurRadius: 5),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _moveMapTo(LatLng point, double zoom) {
    final mapController = _mapLibreController;
    if (_is3dMode && (mapController == null || !_mapLibreStyleReady)) {
      _pendingMapTarget = point;
      _pendingMapZoom = zoom;
      return;
    }
    if (_is3dMode && mapController != null) {
      unawaited(
        mapController
            .animateCamera(
              maplibre.CameraUpdate.newCameraPosition(
                maplibre.CameraPosition(
                  target: maplibre.LatLng(point.latitude, point.longitude),
                  zoom: zoom,
                  tilt: _isMap3dView ? 55 : 0,
                  bearing: _isMap3dView ? 20 : 0,
                ),
              ),
              duration: const Duration(milliseconds: 850),
            )
            .then<void>((_) {})
            .catchError((Object error) {
              debugPrint('Could not animate 3D map camera: $error');
            }),
      );
      return;
    }
    _mapController.move(point, zoom);
  }

  void _toggleMapPerspective() {
    if (!_is3dMode) return;
    final show3d = !_isMap3dView;
    setState(() => _isMap3dView = show3d);

    final controller = _mapLibreController;
    if (controller == null) return;
    final camera = controller.cameraPosition;
    final target = camera?.target ?? const maplibre.LatLng(6.8565, 79.8728);
    unawaited(
      controller
          .animateCamera(
            maplibre.CameraUpdate.newCameraPosition(
              maplibre.CameraPosition(
                target: target,
                zoom: camera?.zoom ?? 17,
                tilt: show3d ? 55 : 0,
                bearing: show3d ? 20 : 0,
              ),
            ),
            duration: const Duration(milliseconds: 650),
          )
          .then<void>((_) {})
          .catchError((Object error) {
            debugPrint('Could not change map perspective: $error');
          }),
    );
  }

  void _resetMapNorth() {
    final controller = _mapLibreController;
    if (controller == null) return;

    final current =
        controller.cameraPosition ??
        maplibre.CameraPosition(
          target: const maplibre.LatLng(6.8565, 79.8728),
          zoom: 17,
          tilt: _isMap3dView ? 55 : 0,
        );
    unawaited(
      controller
          .animateCamera(
            maplibre.CameraUpdate.newCameraPosition(
              maplibre.CameraPosition(
                target: current.target,
                zoom: current.zoom,
                tilt: current.tilt,
                bearing: 0,
              ),
            ),
            duration: const Duration(milliseconds: 450),
          )
          .then<void>((_) {
            _mapCompassBearing.value = 0;
          })
          .catchError((Object error) {
            debugPrint('Could not reset map direction: $error');
          }),
    );
  }

  bool _isInsideZooArea(LatLng point) {
    final extent = _zooVisitExtent;
    if (extent == null) return true;

    // Tighten the recorded zoo footprint slightly so locations just outside
    // its edge do not count as an in-zoo visit.
    const edgeBufferMeters = 12.0;
    final latitudeBuffer = edgeBufferMeters / 111320;
    final longitudeBuffer =
        edgeBufferMeters /
        (111320 * math.cos(point.latitude * math.pi / 180).abs());
    return point.latitude >= extent.south + latitudeBuffer &&
        point.latitude <= extent.north - latitudeBuffer &&
        point.longitude >= extent.west + longitudeBuffer &&
        point.longitude <= extent.east - longitudeBuffer;
  }

  Map<String, dynamic> _waypointsGeoJson(List<ZooWaypoint> waypoints) {
    final explorationTargetId = _explorationSession == null
        ? null
        : _nextExplorationDestination(_allWaypoints)?.waypoint.id;
    return {
      'type': 'FeatureCollection',
      'features': waypoints.map((waypoint) {
        return {
          'type': 'Feature',
          'id': waypoint.id,
          'properties': {
            'id': waypoint.id,
            'name': waypoint.name,
            'category': waypoint.category.toLowerCase(),
            'discovered':
                waypoint.category.toLowerCase() == 'animal' &&
                _gamificationProfile.hasDiscovered(waypoint.id),
            'explorationTarget': waypoint.id == explorationTargetId,
            'icon': waypoint.category.toLowerCase() == 'animal'
                ? _enclosureImageId(waypoint)
                : waypoint.category.toLowerCase() == 'facility'
                ? _facilityPinImageId
                : _landmarkPinImageId,
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [waypoint.longitude, waypoint.latitude],
          },
        };
      }).toList(),
    };
  }

  Map<String, dynamic> _routesGeoJson(List<List<LatLng>> routes) => {
    'type': 'FeatureCollection',
    'features': routes.map((route) {
      return {
        'type': 'Feature',
        'properties': const <String, dynamic>{},
        'geometry': {
          'type': 'LineString',
          'coordinates': route
              .map((point) => [point.longitude, point.latitude])
              .toList(),
        },
      };
    }).toList(),
  };

  Map<String, dynamic> _visitorGeoJson(LatLng point, {double? heading}) {
    final features = <Map<String, dynamic>>[];
    if (heading != null) {
      const earthRadiusMeters = 6378137.0;
      const directionLengthMeters = 28.0;
      final latitudeRadians = point.latitude * math.pi / 180;
      final headingRadians = heading * math.pi / 180;
      final angularDistance = directionLengthMeters / earthRadiusMeters;
      final directionLatitude =
          point.latitude +
          (angularDistance * math.cos(headingRadians)) * 180 / math.pi;
      final directionLongitude =
          point.longitude +
          (angularDistance * math.sin(headingRadians)) *
              180 /
              (math.pi * math.cos(latitudeRadians));
      features.add({
        'type': 'Feature',
        'properties': const {'kind': 'heading'},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [point.longitude, point.latitude],
            [directionLongitude, directionLatitude],
          ],
        },
      });
    }
    features.add({
      'type': 'Feature',
      'id': 'visitor',
      'properties': const {'kind': 'position'},
      'geometry': {
        'type': 'Point',
        'coordinates': [point.longitude, point.latitude],
      },
    });
    return {'type': 'FeatureCollection', 'features': features};
  }

  Future<void> _onMapLibreStyleLoaded(ZooMapData data) async {
    final controller = _mapLibreController;
    if (controller == null) return;

    try {
      await _hideBaseMapBuildingsAndPoiLayers(controller);
      var zooIllustrationsReady = true;
      try {
        for (final waypoint in data.waypoints.where(
          (waypoint) => waypoint.category.toLowerCase() == 'animal',
        )) {
          await controller.addImage(
            _enclosureImageId(waypoint),
            await _renderMapEnclosure(waypoint.name),
          );
        }
        await controller.addImage(
          _facilityPinImageId,
          await _renderMapPin('facility'),
        );
        await controller.addImage(
          _landmarkPinImageId,
          await _renderMapPin('landmark'),
        );
      } catch (error) {
        zooIllustrationsReady = false;
        debugPrint(
          'Could not add zoo map illustrations; using simple pins: $error',
        );
      }
      await controller.addGeoJsonSource(
        _routeSourceId,
        _routesGeoJson(data.routes),
      );
      await controller.addGeoJsonSource(
        _waypointSourceId,
        _waypointsGeoJson(_visibleWaypoints.value),
      );
      if (zooIllustrationsReady) {
        try {
          await controller.addSymbolLayer(
            _waypointSourceId,
            'zoo-animal-enclosures-and-locations',
            const maplibre.SymbolLayerProperties(
              iconImage: ['get', 'icon'],
              iconOpacity: 1,
              iconSize: [
                'interpolate',
                ['linear'],
                ['zoom'],
                17,
                0.52,
                18,
                0.70,
                19,
                0.92,
                20,
                1.18,
              ],
              iconAnchor: 'bottom',
              iconAllowOverlap: true,
              iconIgnorePlacement: true,
              iconOptional: true,
              iconPitchAlignment: 'viewport',
              iconRotationAlignment: 'viewport',
            ),
            minzoom: 16.5,
            filter: [
              '==',
              ['get', 'category'],
              'animal',
            ],
          );
          await controller.addSymbolLayer(
            _waypointSourceId,
            'zoo-facility-locations',
            const maplibre.SymbolLayerProperties(
              iconImage: ['get', 'icon'],
              iconSize: 0.24,
              iconAnchor: 'bottom',
              iconAllowOverlap: true,
              iconIgnorePlacement: true,
              textField: ['get', 'name'],
              textFont: ['Noto Sans Regular'],
              textSize: 11,
              textColor: '#234E38',
              textHaloColor: '#FFFDF4',
              textHaloWidth: 2,
              textAnchor: 'bottom',
              textOffset: [0, 0.35],
              textAllowOverlap: false,
              textOptional: true,
            ),
            minzoom: 16.5,
            filter: [
              '==',
              ['get', 'category'],
              'facility',
            ],
          );
          await controller.addSymbolLayer(
            _waypointSourceId,
            'zoo-landmark-locations',
            const maplibre.SymbolLayerProperties(
              iconImage: ['get', 'icon'],
              iconSize: 0.3,
              iconAnchor: 'bottom',
              iconAllowOverlap: true,
              iconIgnorePlacement: true,
              textField: ['get', 'name'],
              textFont: ['Noto Sans Regular'],
              textSize: 11,
              textColor: '#234E38',
              textHaloColor: '#FFFDF4',
              textHaloWidth: 2,
              textAnchor: 'bottom',
              textOffset: [0, 0.35],
              textAllowOverlap: false,
              textOptional: true,
            ),
            minzoom: 16.5,
            filter: [
              '==',
              ['get', 'category'],
              'landmark',
            ],
          );
        } catch (error) {
          zooIllustrationsReady = false;
          debugPrint(
            'Could not add zoo illustration layer; using simple pins: $error',
          );
        }
      }
      if (!zooIllustrationsReady) {
        await controller.addCircleLayer(
          _waypointSourceId,
          'zoo-waypoint-fallback',
          const maplibre.CircleLayerProperties(
            circleRadius: 7,
            circleColor: '#286A45',
            circleStrokeColor: '#FFFDF2',
            circleStrokeWidth: 2,
          ),
          minzoom: 16.5,
        );
      }
      // Place the route explicitly beneath the waypoint icons. Adding layers
      // in order alone can vary across MapLibre platforms and map styles.
      final routeBelowLayerId = zooIllustrationsReady
          ? 'zoo-animal-enclosures-and-locations'
          : 'zoo-waypoint-fallback';
      if (!widget.isDarkMode) {
        await controller.addLineLayer(
          _routeSourceId,
          'zoo-route-outline',
          const maplibre.LineLayerProperties(
            lineColor: '#FFFDF2',
            lineWidth: 9,
            lineOpacity: 0.94,
            lineCap: 'round',
            lineJoin: 'round',
          ),
          belowLayerId: routeBelowLayerId,
        );
      }
      await controller.addLineLayer(
        _routeSourceId,
        'zoo-route-lines',
        const maplibre.LineLayerProperties(
          lineColor: '#E1A72E',
          lineWidth: 5,
          lineOpacity: 1,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        belowLayerId: routeBelowLayerId,
      );
      await controller.addCircleLayer(
        _waypointSourceId,
        'zoo-exploration-destination-ring',
        const maplibre.CircleLayerProperties(
          circleRadius: 31,
          circleColor: '#FFC857',
          circleOpacity: 0.32,
          circleStrokeColor: '#D69119',
          circleStrokeWidth: 3,
        ),
        belowLayerId: routeBelowLayerId,
        minzoom: 16.5,
        filter: [
          'all',
          [
            '==',
            ['get', 'category'],
            'animal',
          ],
          [
            '==',
            ['get', 'explorationTarget'],
            true,
          ],
        ],
        enableInteraction: false,
      );
      await controller.addGeoJsonSource(
        _visitorSourceId,
        _currentPosition == null
            ? _emptyGeoJson
            : _visitorGeoJson(
                _currentPosition!,
                heading: _visitorHeadingDegrees,
              ),
      );
      await controller.addLineLayer(
        _visitorSourceId,
        'visitor-location-heading',
        const maplibre.LineLayerProperties(
          lineColor: '#2878D0',
          lineOpacity: 0.72,
          lineWidth: 5,
          lineCap: 'round',
        ),
        filter: [
          '==',
          ['get', 'kind'],
          'heading',
        ],
        enableInteraction: false,
      );
      await controller.addCircleLayer(
        _visitorSourceId,
        'visitor-location-point',
        const maplibre.CircleLayerProperties(
          circleRadius: 8,
          circleColor: '#2878D0',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3,
        ),
        enableInteraction: false,
      );
      if (mounted && identical(_mapLibreController, controller)) {
        _mapLibreStyleReady = true;
        final pendingTarget = _pendingMapTarget;
        if (pendingTarget != null) {
          _pendingMapTarget = null;
          _moveMapTo(pendingTarget, _pendingMapZoom);
        }
      }
    } catch (error) {
      debugPrint('Could not load 3D zoo map layers: $error');
      _showMessage(
        'Could not load the 3D map. Check your internet connection.',
      );
    }
  }

  static const _emptyGeoJson = <String, dynamic>{
    'type': 'FeatureCollection',
    'features': <dynamic>[],
  };

  Future<void> _hideBaseMapBuildingsAndPoiLayers(
    maplibre.MapLibreMapController controller,
  ) async {
    try {
      final layerIds = await controller.getLayerIds();
      for (final layerId in layerIds) {
        final normalizedId = layerId.toString().toLowerCase();
        if (normalizedId.contains('building') ||
            normalizedId.contains('extrusion') ||
            normalizedId.contains('poi')) {
          await controller.setLayerVisibility(layerId.toString(), false);
        }
      }
    } catch (error) {
      // Keep the map usable if the remote style does not expose layer ids.
      debugPrint('Could not clean up base map layers: $error');
    }
  }

  Future<Uint8List> _renderMapPin(String category) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    ZooMapPinPainter(category).paint(canvas, const Size(128, 152));
    final picture = recorder.endRecording();
    final image = await picture.toImage(128, 152);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<Uint8List> _renderMapEnclosure(String animalName) async {
    final frame = _cartoonFrameFor(animalName);
    final atlas = await _cartoonAtlasImage(frame ~/ 16 + 1);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    ZooEnclosurePainter(
      animalName,
      includeAnimal: false,
    ).paint(canvas, const Size(128, 104));
    final cellSize = atlas.width / 4;
    final localFrame = frame % 16;
    canvas.drawImageRect(
      atlas,
      Rect.fromLTWH(
        localFrame % 4 * cellSize,
        localFrame ~/ 4 * cellSize,
        cellSize,
        cellSize,
      ),
      const Rect.fromLTWH(14, 2, 100, 100),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(128, 104);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (data == null) {
      throw StateError('Could not render an enclosure for $animalName');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<ui.Image> _cartoonAtlasImage(int sheet) =>
      _cartoonAtlasCache.putIfAbsent(sheet, () async {
        final data = await rootBundle.load(
          'assets/images/animals/cartoon_animals_$sheet.png',
        );
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        codec.dispose();
        return frame.image;
      });

  void _onMapLibreTap(maplibre.LatLng point) {
    ZooWaypoint? nearest;
    var nearestDistance = double.infinity;
    for (final waypoint in _visibleWaypoints.value) {
      final distance = const Distance().as(
        LengthUnit.Meter,
        LatLng(point.latitude, point.longitude),
        LatLng(waypoint.latitude, waypoint.longitude),
      );
      if (distance < nearestDistance) {
        nearest = waypoint;
        nearestDistance = distance;
      }
    }
    if (nearest != null && nearestDistance < 24) {
      _showWaypointDetails(nearest);
    }
  }

  Widget _buildMapLibre(ZooMapData data) {
    final extent = _zooMapExtent!;
    return maplibre.MapLibreMap(
      styleString: widget.isDarkMode ? _darkMapLibreStyle : _mapLibreStyle,
      initialCameraPosition: maplibre.CameraPosition(
        target: maplibre.LatLng(6.8565, 79.8728),
        zoom: 17,
        tilt: _isMap3dView ? 55 : 0,
        bearing: _isMap3dView ? 20 : 0,
      ),
      cameraTargetBounds: maplibre.CameraTargetBounds(
        maplibre.LatLngBounds(
          southwest: maplibre.LatLng(extent.south, extent.west),
          northeast: maplibre.LatLng(extent.north, extent.east),
        ),
      ),
      minMaxZoomPreference: const maplibre.MinMaxZoomPreference(17, 20),
      foregroundLoadColor: Theme.of(context).scaffoldBackgroundColor,
      translucentTextureSurface: true,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,
      zoomGesturesEnabled: true,
      scrollGesturesEnabled: true,
      compassEnabled: false,
      featureTapsTriggersMapClick: true,
      logoEnabled: false,
      attributionButtonPosition: maplibre.AttributionButtonPosition.bottomRight,
      trackCameraPosition: true,
      onCameraMove: (camera) {
        final bearing = camera.bearing % 360;
        if ((_mapCompassBearing.value - bearing).abs() > 0.5) {
          _mapCompassBearing.value = bearing;
        }
      },
      onMapCreated: (controller) {
        _mapLibreController = controller;
      },
      onStyleLoadedCallback: () => _onMapLibreStyleLoaded(data),
      onMapClick: (_, point) => _onMapLibreTap(point),
    );
  }

  Widget _buildMapSearch() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _isSearchExpanded
          ? KeyedSubtree(
              key: const ValueKey('expanded-zoo-search'),
              child: _buildExpandedMapSearch(),
            )
          : KeyedSubtree(
              key: const ValueKey('collapsed-zoo-search'),
              child: _buildCollapsedMapSearch(),
            ),
    );
  }

  Widget _buildCollapsedMapSearch() {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        color: colors.surface,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _isSearchExpanded = true),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_rounded, color: colors.primary),
                const SizedBox(width: 10),
                const Text('Search the zoo'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedMapSearch() {
    return ValueListenableBuilder<List<ZooWaypoint>>(
      valueListenable: _visibleWaypoints,
      builder: (context, matches, _) {
        final showResults = _searchController.text.trim().isNotEmpty;
        final colors = Theme.of(context).colorScheme;

        return Material(
          color: colors.surface,
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _searchController,
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Find animals, facilities or landmarks',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            tooltip: 'Clear search',
                            onPressed: _searchController.clear,
                            icon: const Icon(Icons.close_rounded),
                          ),
                        IconButton(
                          tooltip: 'Close search',
                          onPressed: () {
                            FocusScope.of(context).unfocus();
                            _selectedCategory = 'Animals';
                            _searchController.clear();
                            setState(() => _isSearchExpanded = false);
                          },
                          icon: const Icon(Icons.keyboard_arrow_up_rounded),
                        ),
                      ],
                    ),
                    filled: true,
                    fillColor: colors.surfaceContainerHighest.withValues(
                      alpha: 0.55,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      for (final category in _categories)
                        FilterChip(
                          label: Text(category),
                          selected: _selectedCategory == category,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) {
                            setState(() => _selectedCategory = category);
                            _updateFilteredWaypoints();
                          },
                        ),
                    ],
                  ),
                ),
                if (showResults)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, left: 4),
                      child: Text(
                        '${matches.length} places',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                  ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: showResults
                      ? Column(
                          children: matches.isEmpty
                              ? [
                                  const Divider(height: 16),
                                  const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text('No matching places found.'),
                                  ),
                                ]
                              : [
                                  const Divider(height: 16),
                                  for (final waypoint in matches.take(4))
                                    ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading:
                                          waypoint.category.toLowerCase() ==
                                              'animal'
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: _buildAnimalIllustration(
                                                waypoint.name,
                                                width: 44,
                                                height: 44,
                                              ),
                                            )
                                          : CircleAvatar(
                                              backgroundColor: _markerColor(
                                                waypoint.category,
                                              ).withValues(alpha: 0.12),
                                              foregroundColor: _markerColor(
                                                waypoint.category,
                                              ),
                                              child: Icon(
                                                _markerIcon(waypoint.category),
                                                size: 20,
                                              ),
                                            ),
                                      title: Text(waypoint.name),
                                      subtitle: _buildWaypointQualityInfo(
                                        waypoint,
                                        fallback: _categoryLabel(
                                          waypoint.category,
                                        ),
                                      ),
                                      trailing: const Icon(
                                        Icons.arrow_forward_ios_rounded,
                                        size: 15,
                                      ),
                                      onTap: () => _selectWaypoint(waypoint),
                                    ),
                                ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Load animal/facility waypoints and the recorded GPS route.
  Future<ZooMapData> _loadMapData() async {
    final files = await Future.wait([
      rootBundle.loadString('assets/data/waypoints_flutter.json'),
      rootBundle.loadString('assets/data/recorded_route.geojson'),
    ]);

    // Load the named locations.
    final waypointJson = jsonDecode(files[0]) as List<dynamic>;

    final waypoints = waypointJson.map((item) {
      return ZooWaypoint.fromJson(Map<String, dynamic>.from(item as Map));
    }).toList();

    // Load the recorded GPS route.
    final routeJson = jsonDecode(files[1]) as Map<String, dynamic>;

    final features = routeJson['features'] as List<dynamic>;
    final routes = <List<LatLng>>[];

    for (final feature in features) {
      final featureMap = Map<String, dynamic>.from(feature as Map);

      final geometry = Map<String, dynamic>.from(featureMap['geometry'] as Map);

      if (geometry['type'] != 'LineString') {
        continue;
      }

      final coordinates = geometry['coordinates'] as List<dynamic>;

      final points = coordinates.map((coordinate) {
        final values = coordinate as List<dynamic>;

        // GeoJSON stores longitude first, latitude second.
        return LatLng(
          (values[1] as num).toDouble(),
          (values[0] as num).toDouble(),
        );
      }).toList();

      // Keep separate route segments separate.
      if (points.length >= 2) {
        routes.add(points);
      }
    }

    return ZooMapData(waypoints: waypoints, routes: routes);
  }

  // Get the phone's current location when the visitor requests it.
  Future<void> _locateMe({bool followUser = true}) async {
    if (_isLocating) return;

    setState(() {
      _isLocating = true;
    });

    try {
      // Check whether the phone's location service is enabled.
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        _showMessage('Please turn on Location in your phone settings.');
        return;
      }

      // Check and request location permission.
      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _showMessage(
          'Location permission was denied. '
          'Allow it to use Locate Me.',
        );
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        _showMessage(
          'Location permission is blocked. '
          'Enable it in this app’s settings.',
        );
        return;
      }

      // Use a balanced fix so GPS acquisition does not wait unnecessarily
      // for a high accuracy reading, and stop waiting after 12 seconds.
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 12),
          ),
        );
      } on TimeoutException {
        // A recent fix is still useful when the device cannot obtain a fresh
        // GPS reading (for example, indoors).
        position = await Geolocator.getLastKnownPosition();
        if (position == null) {
          _showMessage(
            'Could not get a location fix. Check GPS and try again.',
          );
          return;
        }
      }

      if (!mounted) return;

      final point = LatLng(position.latitude, position.longitude);
      if (!_isInsideZooArea(point)) {
        _setVisitorPosition(
          point,
          focusMap: false,
          headingDegrees: _headingFromPosition(position),
        );
        _showOutsideZooMessage();
      } else {
        _setVisitorPosition(
          point,
          focusMap: true,
          headingDegrees: _headingFromPosition(position),
        );
      }

      if (!mounted) return;
      if (followUser && !_isLiveLocationTracking) {
        setState(() => _isLiveLocationTracking = true);
      }
      await _ensurePositionStream();
    } on PermissionDeniedException {
      _showMessage('Location permission is required to use Locate Me.');
    } on LocationServiceDisabledException {
      _showMessage('Please turn on Location in your phone settings.');
    } catch (error) {
      _showMessage('Could not get your location. Check GPS and try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  void _showOutsideZooMessage() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("The tiger can't find you!"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: _buildAnimalIllustration(
                'Bengal Tiger',
                width: 180,
                height: 140,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '“Roar! You seem to be outside Dehiwala Zoo. Come through the '
              'gates, then tap Locate Me and I’ll help you explore!”',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  IconData _markerIcon(String category) {
    switch (category.toLowerCase()) {
      case 'animal':
        return Icons.pets;

      case 'facility':
        return Icons.place;

      default:
        return Icons.location_on;
    }
  }

  Color _markerColor(String category) {
    switch (category.toLowerCase()) {
      case 'animal':
        return Colors.green.shade700;

      case 'facility':
        return Colors.orange.shade800;

      default:
        return Colors.blueGrey;
    }
  }

  String _categoryLabel(String category) => switch (category.toLowerCase()) {
    'animal' => 'Animal',
    'facility' => 'Facility',
    'landmark' => 'Landmark',
    _ => 'Location',
  };

  Widget _buildWaypointQualityInfo(
    ZooWaypoint waypoint, {
    required String fallback,
  }) {
    final colors = Theme.of(context).colorScheme;
    final note = waypoint.reviewNote?.trim();
    final hasNote = note != null && note.isNotEmpty;
    final qualityNotice = !waypoint.nameVerified
        ? 'Name not verified'
        : waypoint.needsReview
        ? 'Details need review'
        : null;
    if (qualityNotice == null && !hasNote) {
      return Text(fallback, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (qualityNotice != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  qualityNotice,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        if (hasNote)
          Text(note)
        else if (qualityNotice == null)
          Text(fallback, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }

  // Display information when a named zoo location is tapped.
  void _showWaypointDetails(ZooWaypoint waypoint) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.outlineVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (waypoint.category.toLowerCase() == 'animal')
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: SizedBox(
                        height: 180,
                        width: double.infinity,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned.fill(
                              child: LayoutBuilder(
                                builder: (context, constraints) =>
                                    _buildAnimalIllustration(
                                      waypoint.name,
                                      width: constraints.maxWidth,
                                      height: constraints.maxHeight,
                                    ),
                              ),
                            ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Color(0xCC101910),
                                  ],
                                  stops: [0.42, 1],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 18,
                              right: 18,
                              bottom: 16,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ANIMAL COLLECTION',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    waypoint.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '3D cartoon character • Habitat discovery',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: _markerColor(waypoint.category)
                              .withValues(alpha: 0.12),
                          foregroundColor: _markerColor(waypoint.category),
                          child: Icon(_markerIcon(waypoint.category), size: 25),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                waypoint.name,
                                style: Theme.of(sheetContext)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                waypoint.category[0].toUpperCase() +
                                    waypoint.category.substring(1),
                                style: Theme.of(sheetContext)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  if (!waypoint.nameVerified ||
                      waypoint.needsReview ||
                      (waypoint.reviewNote?.trim().isNotEmpty ?? false)) ...[
                    const SizedBox(height: 16),
                    _buildWaypointQualityInfo(
                      waypoint,
                      fallback: _categoryLabel(waypoint.category),
                    ),
                  ],
                  if (waypoint.category.toLowerCase() == 'animal') ...[
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: () => _openAnimalCard(waypoint),
                      icon: const Icon(Icons.menu_book_rounded),
                      label: Text(
                        _gamificationProfile.hasDiscovered(waypoint.id)
                            ? 'Open wildlife journal card'
                            : 'View animal profile',
                      ),
                    ),
                    if (_gamificationService.rules.isEligible(waypoint))
                      AnimalDiscoveryAction(
                        waypoint: waypoint,
                        service: _gamificationService,
                        isReady: _gamificationReady,
                        alreadyDiscovered: _gamificationProfile.hasDiscovered(
                          waypoint.id,
                        ),
                        onResult: (result) =>
                            _handleDiscoveryResult(waypoint, result),
                      ),
                    if (_gamificationLoadError != null)
                      Text(
                        'Saved collection progress could not be loaded.',
                        style: Theme.of(sheetContext).textTheme.bodySmall
                            ?.copyWith(color: colors.error),
                      ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _selectTab(1);
                        _moveMapTo(
                          LatLng(waypoint.latitude, waypoint.longitude),
                          18,
                        );
                      },
                      icon: const Icon(Icons.center_focus_strong_rounded),
                      label: const Text('Center map here'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Map coordinates',
                          style: Theme.of(sheetContext).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${waypoint.latitude.toStringAsFixed(6)}, '
                          '${waypoint.longitude.toStringAsFixed(6)}',
                          style: Theme.of(sheetContext).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: FutureBuilder<ZooMapData>(
          future: _mapDataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load the zoo map data.\n\n'
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final data = snapshot.data!;
            final eligibleAnimals = _eligibleAnimals(data.waypoints);
            final nextExplorationDestination = _explorationSession == null
                ? null
                : _nextExplorationDestination(eligibleAnimals);
            _zooMapExtent ??= _boundsFor(data);
            if (_allWaypoints.isEmpty && data.waypoints.isNotEmpty) {
              _allWaypoints = data.waypoints;
              _visibleWaypoints.value = _filterWaypoints(_allWaypoints);
            }
            final tileLayer = TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.dehiwala_zoo_app',
            );
            final fallbackMapTiles = widget.isDarkMode
                ? ColorFiltered(
                    colorFilter: _darkTileColorFilter,
                    child: tileLayer,
                  )
                : tileLayer;

            final mapPage = Stack(
              children: [
                _is3dMode
                    ? _buildMapLibre(data)
                    : FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: LatLng(6.8565, 79.8728),
                          initialZoom: 17,
                          minZoom: 17,
                          maxZoom: 19,
                          onPositionChanged: (camera, _) {
                            if ((_flutterMapZoom.value - camera.zoom).abs() >=
                                0.025) {
                              _flutterMapZoom.value = camera.zoom;
                            }
                          },
                          cameraConstraint: CameraConstraint.containCenter(
                            bounds: LatLngBounds(
                              LatLng(_zooMapExtent!.south, _zooMapExtent!.west),
                              LatLng(_zooMapExtent!.north, _zooMapExtent!.east),
                            ),
                          ),
                        ),
                        children: [
                          // Geographic map background.
                          fallbackMapTiles,

                          // Keep GPS route strokes below the waypoint marker
                          // layer so animal enclosures stay unobscured.
                          if (!widget.isDarkMode)
                            PolylineLayer(
                              simplificationTolerance: 1,
                              polylines: data.routes
                                  .map(
                                    (route) => Polyline(
                                      points: route,
                                      color: const Color(0xFFFFFBEB),
                                      strokeWidth: 10,
                                    ),
                                  )
                                  .toList(),
                            ),
                          PolylineLayer(
                            simplificationTolerance: 1,
                            polylines: data.routes
                                .map(
                                  (route) => Polyline(
                                    points: route,
                                    color: const Color(0xFFE1A72E),
                                    strokeWidth: 5,
                                  ),
                                )
                                .toList(),
                          ),

                          if (nextExplorationDestination != null)
                            CircleLayer(
                              circles: [
                                CircleMarker(
                                  point: LatLng(
                                    nextExplorationDestination
                                        .waypoint
                                        .latitude,
                                    nextExplorationDestination
                                        .waypoint
                                        .longitude,
                                  ),
                                  radius: 31,
                                  useRadiusInMeter: false,
                                  color: const Color(0x52FFC857),
                                  borderColor: const Color(0xFFD69119),
                                  borderStrokeWidth: 3,
                                ),
                              ],
                            ),

                          // Named animal and facility locations.
                          ValueListenableBuilder<List<ZooWaypoint>>(
                            valueListenable: _visibleWaypoints,
                            builder: (context, waypoints, _) => ValueListenableBuilder<double>(
                              valueListenable: _flutterMapZoom,
                              builder: (context, zoom, _) {
                                final animalScale = (1.15 + (zoom - 17) * 0.25)
                                    .clamp(1.15, 1.65)
                                    .toDouble();
                                const maxAnimalScale = 1.65;
                                return MarkerLayer(
                                  markers: waypoints.map((waypoint) {
                                    final isAnimal =
                                        waypoint.category.toLowerCase() ==
                                        'animal';
                                    final markerWidth = isAnimal
                                        ? 62 * maxAnimalScale
                                        : 48.0;
                                    final markerHeight = isAnimal
                                        ? 52 * maxAnimalScale
                                        : 58.0;
                                    return Marker(
                                      point: LatLng(
                                        waypoint.latitude,
                                        waypoint.longitude,
                                      ),
                                      width: markerWidth,
                                      height: markerHeight,
                                      alignment: Alignment.bottomCenter,
                                      child: Semantics(
                                        button: true,
                                        label: waypoint.name,
                                        child: GestureDetector(
                                          onTap: () =>
                                              _showWaypointDetails(waypoint),
                                          child: isAnimal
                                              ? Transform.scale(
                                                  scale:
                                                      animalScale /
                                                      maxAnimalScale,
                                                  alignment:
                                                      Alignment.bottomCenter,
                                                  child: SizedBox(
                                                    width: markerWidth,
                                                    height: markerHeight,
                                                    child: Stack(
                                                      children: [
                                                        Positioned.fill(
                                                          child: CustomPaint(
                                                            painter:
                                                                ZooEnclosurePainter(
                                                                  waypoint.name,
                                                                  includeAnimal:
                                                                      false,
                                                                ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          left:
                                                              11 *
                                                              maxAnimalScale,
                                                          top:
                                                              7 *
                                                              maxAnimalScale,
                                                          child: _buildAnimalSpriteCrop(
                                                            waypoint.name,
                                                            size:
                                                                40 *
                                                                maxAnimalScale,
                                                          ),
                                                        ),
                                                        if (_gamificationProfile
                                                            .hasDiscovered(
                                                              waypoint.id,
                                                            ))
                                                          Positioned(
                                                            top: maxAnimalScale,
                                                            right:
                                                                maxAnimalScale,
                                                            child: Container(
                                                              width:
                                                                  18 *
                                                                  maxAnimalScale,
                                                              height:
                                                                  18 *
                                                                  maxAnimalScale,
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    const Color(
                                                                      0xFF21814D,
                                                                    ),
                                                                shape: BoxShape
                                                                    .circle,
                                                                border: Border.all(
                                                                  color: Colors
                                                                      .white,
                                                                  width:
                                                                      1.5 *
                                                                      maxAnimalScale,
                                                                ),
                                                              ),
                                                              child: Icon(
                                                                Icons
                                                                    .check_rounded,
                                                                size:
                                                                    12 *
                                                                    maxAnimalScale,
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                )
                                              : CustomPaint(
                                                  size: const Size(38, 46),
                                                  painter: ZooMapPinPainter(
                                                    waypoint.category,
                                                  ),
                                                  child: const SizedBox(
                                                    width: 38,
                                                    height: 46,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ),

                          // Visitor's current position.
                          if (_currentPosition != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _currentPosition!,
                                  width: 48,
                                  height: 48,
                                  child: _buildVisitorLocationMarker(),
                                ),
                              ],
                            ),

                          // Required OpenStreetMap attribution.
                          RichAttributionWidget(
                            attributions: [
                              TextSourceAttribution(
                                '© OpenStreetMap contributors',
                              ),
                            ],
                          ),
                        ],
                      ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [_buildMapSearch()],
                  ),
                ),
                if (!_isSearchExpanded)
                  Positioned(
                    top: 68,
                    left: 12,
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topLeft,
                      child: ExplorationSessionPanel(
                        key: ValueKey(_explorationSession != null),
                        isActive: _explorationSession != null,
                        isMinimized: _isExplorationPanelMinimized,
                        isFindingLocation: _isLocating,
                        totalXp: _gamificationProfile.totalXp,
                        discoveredCount: _discoveredEligibleCount(
                          eligibleAnimals,
                        ),
                        eligibleAnimalCount: eligibleAnimals.length,
                        sessionDiscoveryCount:
                            _explorationSession?.discoveryCount ?? 0,
                        sessionXp: _explorationSession?.xpEarned ?? 0,
                        destinationName:
                            nextExplorationDestination?.waypoint.name,
                        distanceMeters:
                            nextExplorationDestination?.distanceMeters,
                        destinationNameVerified:
                            nextExplorationDestination?.waypoint.nameVerified ??
                            false,
                        hasRecordedTrace: data.routes.isNotEmpty,
                        onStart: () => unawaited(_startExploration()),
                        onFinish: () => unawaited(_finishExploration()),
                        onToggleMinimized: () => setState(
                          () => _isExplorationPanelMinimized =
                              !_isExplorationPanelMinimized,
                        ),
                        onOpenCollection: () => _selectTab(5),
                      ),
                    ),
                  ),
                if (!_isSearchExpanded)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Material(
                      color: colors.surface.withValues(alpha: 0.97),
                      elevation: 5,
                      shadowColor: Colors.black.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_is3dMode) ...[
                              Tooltip(
                                message: _isMap3dView
                                    ? 'Switch to 2D'
                                    : 'Switch to 3D',
                                child: FilledButton.tonalIcon(
                                  onPressed: _toggleMapPerspective,
                                  icon: Icon(
                                    _isMap3dView
                                        ? Icons.view_in_ar_rounded
                                        : Icons.map_outlined,
                                    size: 18,
                                  ),
                                  label: Text(_isMap3dView ? '3D' : '2D'),
                                  style: FilledButton.styleFrom(
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    backgroundColor: Colors.transparent,
                                    foregroundColor: colors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                            ],
                            _themeToggleButton(),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (!_isSearchExpanded && _is3dMode)
                  Positioned(
                    top: 84,
                    right: 12,
                    child: _buildMapCompass(colors),
                  ),
              ],
            );
            return IndexedStack(
              index: _selectedTab,
              children: [
                ZooHomeScreen(
                  animals: eligibleAnimals,
                  profile: _gamificationProfile,
                  animalGroupForName: _animalGroup,
                  onOpenMap: () => _selectTab(1),
                  onOpenMapSearch: () {
                    _selectedCategory = 'All';
                    _searchController.clear();
                    _updateFilteredWaypoints();
                    _selectTab(1);
                    setState(() => _isSearchExpanded = true);
                  },
                  onOpenAnimals: () => _selectTab(2),
                  onOpenFacilities: () => _selectTab(3),
                  onOpenLandmarks: () => _selectTab(4),
                  onOpenCollection: () => _selectTab(5),
                  onOpenAnimal: _openAnimalCard,
                  onToggleTheme: widget.onToggleTheme ?? () {},
                  isDarkMode: widget.isDarkMode,
                ),
                mapPage,
                _buildDirectory(data, 'animal'),
                _buildDirectory(data, 'facility'),
                _buildDirectory(data, 'landmark'),
                WildlifeCollectionScreen(
                  animals: eligibleAnimals,
                  profile: _gamificationProfile,
                  onOpenAnimal: (animal) => _openAnimalCard(animal),
                  onShowOnMap: _focusAnimalOnMap,
                ),
              ],
            );
          },
        ),
      ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: _selectTab,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        backgroundColor: colors.surface,
        indicatorColor: colors.primaryContainer,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.pets_outlined),
            selectedIcon: Icon(Icons.pets_rounded),
            label: 'Animals',
          ),
          NavigationDestination(
            icon: Icon(Icons.place_outlined),
            selectedIcon: Icon(Icons.place_rounded),
            label: 'Facilities',
          ),
          NavigationDestination(
            icon: Icon(Icons.landscape_outlined),
            selectedIcon: Icon(Icons.landscape_rounded),
            label: 'Landmarks',
          ),
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark_rounded),
            label: 'Collection',
          ),
        ],
      ),

      // Button to start or pause live visitor location tracking.
      floatingActionButton: _selectedTab == 1
          ? FloatingActionButton.extended(
              onPressed: _isLocating ? null : _handleLocateMePressed,
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
              elevation: 5,
              shape: const StadiumBorder(),
              icon: _isLocating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      _isLiveLocationTracking
                          ? Icons.gps_fixed_rounded
                          : Icons.my_location,
                    ),
              label: Text(
                _isLocating
                    ? 'Locating...'
                    : _isLiveLocationTracking
                    ? 'Tracking'
                    : 'Locate Me',
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }
}

typedef ZooMapExtent = ({double south, double west, double north, double east});

class _VisitorHeadingPainter extends CustomPainter {
  const _VisitorHeadingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final blue = const Color(0xFF2878D0);
    final cone = ui.Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx - 8, 5)
      ..lineTo(center.dx, 1)
      ..lineTo(center.dx + 8, 5)
      ..close();
    canvas.drawPath(cone, Paint()..color = blue.withValues(alpha: 0.24));

    final arrow = ui.Path()
      ..moveTo(center.dx, 1)
      ..lineTo(center.dx - 7, 19)
      ..lineTo(center.dx, 15)
      ..lineTo(center.dx + 7, 19)
      ..close();
    canvas.drawPath(
      arrow,
      Paint()
        ..color = blue
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      arrow,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _VisitorHeadingPainter oldDelegate) => false;
}

class AnimalHabitatBackdropPainter extends CustomPainter {
  final String animalName;

  const AnimalHabitatBackdropPainter(this.animalName);

  @override
  void paint(Canvas canvas, Size size) {
    final name = animalName.toLowerCase();
    final water = const [
      'swan',
      'hippopotamus',
      'otter',
      'capybara',
    ].any(name.contains);
    final forest = const [
      'monkey',
      'langur',
      'lemur',
      'tiger',
      'jaguar',
      'bear',
      'fox',
      'cat',
      'boar',
      'chimpanzee',
      'baboon',
      'macaw',
    ].any(name.contains);
    final farm = const [
      'sheep',
      'horse',
      'donkey',
      'mule',
      'llama',
    ].any(name.contains);

    final sky = water
        ? const Color(0xFFBDE9E8)
        : forest
        ? const Color(0xFFB5DDBA)
        : const Color(0xFFB9E3F2);
    final horizon = water
        ? const Color(0xFF82C5B7)
        : forest
        ? const Color(0xFF82B779)
        : farm
        ? const Color(0xFFB8D987)
        : const Color(0xFFE6C979);
    final foreground = water
        ? const Color(0xFF4FA6A6)
        : forest
        ? const Color(0xFF4F955D)
        : farm
        ? const Color(0xFF84B96B)
        : const Color(0xFFC4A951);

    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(size.width, size.height),
          [sky, horizon],
        ),
    );
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.2),
      size.shortestSide * 0.09,
      Paint()..color = const Color(0xFFFFF3C7).withValues(alpha: 0.8),
    );
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.52);
    canvas.drawCircle(
      Offset(size.width * 0.2, size.height * 0.18),
      size.shortestSide * 0.055,
      cloud,
    );
    canvas.drawCircle(
      Offset(size.width * 0.25, size.height * 0.17),
      size.shortestSide * 0.075,
      cloud,
    );
    canvas.drawCircle(
      Offset(size.width * 0.3, size.height * 0.19),
      size.shortestSide * 0.05,
      cloud,
    );

    final distantHill = ui.Path()
      ..moveTo(0, size.height * 0.62)
      ..quadraticBezierTo(
        size.width * 0.3,
        size.height * 0.42,
        size.width * 0.56,
        size.height * 0.61,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.47,
        size.width,
        size.height * 0.59,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(distantHill, Paint()..color = horizon);

    if (water) {
      final lake = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, size.height * 0.63),
          Offset(0, size.height),
          const [Color(0xFF6FBAB5), Color(0xFF4F9E9D)],
        );
      canvas.drawRect(
        Rect.fromLTWH(0, size.height * 0.63, size.width, size.height * 0.37),
        lake,
      );
      final ripple = Paint()
        ..color = const Color(0x99D9F1D9)
        ..strokeWidth = math.max(1, size.shortestSide * 0.009)
        ..strokeCap = StrokeCap.round;
      for (var row = 0; row < 4; row++) {
        final y = size.height * (0.71 + row * 0.065);
        canvas.drawLine(
          Offset(size.width * (0.12 + row * 0.06), y),
          Offset(size.width * (0.34 + row * 0.05), y),
          ripple,
        );
      }
      for (final lily in [
        Offset(size.width * 0.16, size.height * 0.7),
        Offset(size.width * 0.81, size.height * 0.83),
      ]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: lily,
            width: size.shortestSide * 0.2,
            height: size.shortestSide * 0.065,
          ),
          Paint()..color = const Color(0xFF73B96F),
        );
        canvas.drawCircle(
          Offset(lily.dx + size.shortestSide * 0.035, lily.dy - 2),
          size.shortestSide * 0.022,
          Paint()..color = const Color(0xFFFFD5E5),
        );
      }
    } else if (forest) {
      final trunk = Paint()
        ..color = const Color(0xFF755D45)
        ..strokeWidth = math.max(3, size.width * 0.035)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(size.width * 0.07, size.height * 0.25),
        Offset(size.width * 0.07, size.height),
        trunk,
      );
      canvas.drawLine(
        Offset(size.width * 0.94, size.height * 0.3),
        Offset(size.width * 0.94, size.height),
        trunk,
      );
      for (final leaf in [
        Offset(size.width * 0.03, size.height * 0.23),
        Offset(size.width * 0.11, size.height * 0.18),
        Offset(size.width * 0.9, size.height * 0.22),
        Offset(size.width * 0.97, size.height * 0.16),
      ]) {
        canvas.drawCircle(
          leaf,
          size.shortestSide * 0.15,
          Paint()..color = const Color(0xFF6CA66B).withValues(alpha: 0.8),
        );
      }
      final blossomColors = [
        const Color(0xFFFFD166),
        const Color(0xFFFF8E9E),
        const Color(0xFFF4F0A3),
      ];
      for (var flower = 0; flower < 3; flower++) {
        final center = Offset(
          size.width * (0.16 + flower * 0.34),
          size.height * (0.83 + (flower.isEven ? 0.05 : 0)),
        );
        final stem = Paint()
          ..color = const Color(0xFF387D52)
          ..strokeWidth = math.max(1.0, size.shortestSide * 0.012)
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          center,
          Offset(center.dx, center.dy + size.height * 0.09),
          stem,
        );
        canvas.drawCircle(
          center,
          size.shortestSide * 0.035,
          Paint()..color = blossomColors[flower],
        );
      }
    } else {
      final foregroundHill = ui.Path()
        ..moveTo(0, size.height * 0.78)
        ..quadraticBezierTo(
          size.width * 0.47,
          size.height * 0.6,
          size.width,
          size.height * 0.76,
        )
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(foregroundHill, Paint()..color = foreground);
      final grass = Paint()
        ..color = Color.lerp(foreground, Colors.white, 0.28)!
        ..strokeWidth = math.max(1, size.shortestSide * 0.008)
        ..strokeCap = StrokeCap.round;
      for (var blade = 0; blade < 10; blade++) {
        final x = size.width * (0.04 + blade * 0.102);
        final y = size.height * (0.87 + (blade.isEven ? 0.08 : 0));
        canvas.drawLine(
          Offset(x, y),
          Offset(x - size.width * 0.018, y - size.height * 0.09),
          grass,
        );
      }
      const flowerColors = [
        Color(0xFFFF8EA1),
        Color(0xFFFFD166),
        Color(0xFFF4F5E8),
        Color(0xFFB9A3F4),
      ];
      for (var flower = 0; flower < flowerColors.length; flower++) {
        final center = Offset(
          size.width * (0.14 + flower * 0.23),
          size.height * (0.82 + (flower.isEven ? 0.06 : 0)),
        );
        canvas.drawLine(
          center,
          Offset(center.dx, center.dy + size.height * 0.08),
          grass,
        );
        canvas.drawCircle(
          center,
          size.shortestSide * 0.032,
          Paint()..color = flowerColors[flower],
        );
      }
    }

    // Layer colorful low foliage around the outside of the portrait so each
    // habitat feels lush without covering or changing the animal artwork.
    final shrubPaint = Paint();
    final shrubCenters = [
      Offset(size.width * 0.02, size.height * 0.88),
      Offset(size.width * 0.97, size.height * 0.9),
      Offset(size.width * 0.1, size.height * 0.96),
      Offset(size.width * 0.88, size.height * 0.97),
    ];
    final shrubColors = water
        ? const [Color(0xFF388C69), Color(0xFF63AE73)]
        : const [Color(0xFF287A4F), Color(0xFF48A65B)];
    for (var i = 0; i < shrubCenters.length; i++) {
      final center = shrubCenters[i];
      final radius = size.shortestSide * (i.isEven ? 0.105 : 0.085);
      shrubPaint.color = shrubColors[i % shrubColors.length];
      canvas.drawCircle(center, radius, shrubPaint);
      canvas.drawCircle(
        center.translate(radius * 0.62, -radius * 0.35),
        radius * 0.72,
        shrubPaint
          ..color = Color.lerp(
            shrubColors[i % shrubColors.length],
            Colors.white,
            0.18,
          )!,
      );
    }
    final accentColors = const [
      Color(0xFFFFD166),
      Color(0xFFFF7FA3),
      Color(0xFFB9A3F4),
      Color(0xFFFFF0A8),
    ];
    for (var i = 0; i < 8; i++) {
      final x = size.width * (0.08 + (i % 4) * 0.27);
      final y = size.height * (0.94 + (i.isEven ? 0.025 : -0.015));
      final center = Offset(x, y);
      final petal = size.shortestSide * 0.018;
      final color = Paint()..color = accentColors[i % accentColors.length];
      for (var petalIndex = 0; petalIndex < 4; petalIndex++) {
        final angle = petalIndex * math.pi / 2;
        canvas.drawCircle(
          center.translate(math.cos(angle) * petal, math.sin(angle) * petal),
          petal * 0.72,
          color,
        );
      }
      canvas.drawCircle(
        center,
        petal * 0.42,
        Paint()..color = const Color(0xFFFFE9A8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant AnimalHabitatBackdropPainter oldDelegate) =>
      oldDelegate.animalName != animalName;
}

class ZooEnclosurePainter extends CustomPainter {
  final String animalName;
  final bool includeAnimal;

  const ZooEnclosurePainter(this.animalName, {this.includeAnimal = true});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 128, size.height / 104);
    canvas.translate(0, 20);

    final name = animalName.toLowerCase();
    final isBird = const [
      'ostrich',
      'crane',
      'cassowary',
      'swan',
      'macaw',
      'kite',
      'eagle',
      'emu',
      'parrot',
      'peacock',
    ].any(name.contains);
    final animalColor = name.contains('tiger')
        ? const Color(0xFFF28A37)
        : name.contains('lion')
        ? const Color(0xFFD49A50)
        : name.contains('elephant')
        ? const Color(0xFF8A9CA0)
        : name.contains('giraffe')
        ? const Color(0xFFE8B849)
        : name.contains('zebra')
        ? const Color(0xFFECE7D8)
        : name.contains('monkey') || name.contains('ape')
        ? const Color(0xFF9B6242)
        : isBird
        ? const Color(0xFF4796B1)
        : const Color(0xFF8B7B58);

    ui.Path polygon(List<Offset> points) => ui.Path()
      ..moveTo(points.first.dx, points.first.dy)
      ..addPolygon(points.skip(1).toList(), true);

    final leftFace = polygon(const [
      Offset(14, 47),
      Offset(64, 72),
      Offset(64, 84),
      Offset(14, 59),
    ]);
    final rightFace = polygon(const [
      Offset(64, 72),
      Offset(114, 47),
      Offset(114, 59),
      Offset(64, 84),
    ]);
    final top = polygon(const [
      Offset(64, 17),
      Offset(114, 46),
      Offset(64, 72),
      Offset(14, 46),
    ]);

    canvas.drawShadow(top, const Color(0x55313F33), 5, true);
    canvas.drawPath(leftFace, Paint()..color = const Color(0xFF37754E));
    canvas.drawPath(rightFace, Paint()..color = const Color(0xFF28633F));
    canvas.drawPath(
      top,
      Paint()
        ..shader = ui.Gradient.linear(Offset(35, 24), Offset(90, 72), [
          Color(0xFFA8D887),
          Color(0xFF70B96B),
        ]),
    );
    canvas.drawPath(
      top,
      Paint()
        ..color = const Color(0xFF4E925B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Add a colorful habitat border so the map feels like a place to explore,
    // while keeping the middle of the enclosure clear for the animal sprite.
    void drawLeafCluster(Offset center, Color color, double scale) {
      final leafPaint = Paint()..color = color;
      for (final leaf in const [
        Offset(-4, 1),
        Offset(0, -2),
        Offset(4, 1),
        Offset(0, 3),
      ]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: center + leaf * scale,
            width: 6.5 * scale,
            height: 4.2 * scale,
          ),
          leafPaint,
        );
      }
      canvas.drawCircle(
        center,
        1.2 * scale,
        Paint()..color = Color.lerp(color, Colors.white, 0.48)!,
      );
    }

    void drawFlower(Offset center, Color color) {
      final petalPaint = Paint()..color = color;
      for (var petal = 0; petal < 5; petal++) {
        final angle = petal * math.pi * 2 / 5;
        canvas.drawCircle(
          center + Offset(math.cos(angle), math.sin(angle)) * 2.2,
          1.8,
          petalPaint,
        );
      }
      canvas.drawCircle(center, 1.35, Paint()..color = const Color(0xFFFFD35E));
    }

    drawLeafCluster(const Offset(28, 48), const Color(0xFF2F8655), 1.25);
    drawLeafCluster(const Offset(36, 56), const Color(0xFF55A95F), 0.9);
    drawLeafCluster(const Offset(92, 56), const Color(0xFF398F58), 1.05);
    drawLeafCluster(const Offset(101, 48), const Color(0xFF66B963), 1.15);
    drawLeafCluster(const Offset(48, 65), const Color(0xFF65B968), 0.72);
    drawLeafCluster(const Offset(82, 65), const Color(0xFF4FA45E), 0.75);

    // A few bright flowers and smooth stones give each habitat a collectible,
    // illustrated feel without adding detail beneath the animal itself.
    drawFlower(const Offset(35, 46), const Color(0xFFFF78A7));
    drawFlower(const Offset(94, 47), const Color(0xFFFFD166));
    drawFlower(const Offset(45, 63), const Color(0xFFB884F2));
    drawFlower(const Offset(82, 63), const Color(0xFFFF8C68));
    for (final stone in const [
      Offset(54, 67),
      Offset(73, 67),
      Offset(99, 56),
    ]) {
      canvas.drawOval(
        Rect.fromCenter(center: stone, width: 6, height: 3.3),
        Paint()..color = const Color(0xFFB8C7A2),
      );
    }

    if (const [
      'swan',
      'hippopotamus',
      'otter',
      'capybara',
    ].any(name.contains)) {
      final pond = ui.Path()
        ..moveTo(51, 61)
        ..quadraticBezierTo(63, 56, 77, 62)
        ..quadraticBezierTo(72, 68, 56, 67)
        ..close();
      canvas.drawPath(pond, Paint()..color = const Color(0xFF70D4D1));
      canvas.drawPath(
        pond,
        Paint()
          ..color = const Color(0xFFA9F0E6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
    }

    // Back fence and posts make the grass tile read as a tiny enclosure.
    final fencePaint = Paint()
      ..color = const Color(0xFF865638)
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final rail = ui.Path()
      ..moveTo(19, 46)
      ..lineTo(64, 21)
      ..lineTo(109, 46);
    canvas.drawPath(rail, fencePaint);
    final lowerRail = ui.Path()
      ..moveTo(23, 52)
      ..lineTo(64, 74)
      ..lineTo(105, 52);
    canvas.drawPath(lowerRail, fencePaint..strokeWidth = 2.5);
    for (final post in const [
      Offset(19, 46),
      Offset(42, 33),
      Offset(64, 21),
      Offset(86, 33),
      Offset(109, 46),
      Offset(23, 52),
      Offset(64, 74),
      Offset(105, 52),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: post, width: 4.5, height: 7),
          const Radius.circular(1.5),
        ),
        Paint()..color = const Color(0xFFA9784E),
      );
    }

    // A small shaded animal silhouette sits in the middle of each habitat.
    if (includeAnimal) {
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(63, 55), width: 30, height: 7),
        Paint()..color = const Color(0x33233928),
      );
      if (isBird) {
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(62, 49), width: 24, height: 17),
          Paint()
            ..shader = ui.Gradient.linear(
              const Offset(52, 42),
              const Offset(70, 58),
              [Color.lerp(animalColor, Colors.white, 0.32)!, animalColor],
            ),
        );
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(61, 49), width: 12, height: 10),
          Paint()..color = Color.lerp(animalColor, Colors.black, 0.16)!,
        );
        canvas.drawCircle(
          const Offset(74, 43),
          7,
          Paint()..color = animalColor,
        );
        canvas.drawCircle(
          const Offset(76, 41),
          1.45,
          Paint()..color = const Color(0xFF25322C),
        );
        canvas.drawPath(
          ui.Path()
            ..moveTo(80, 43)
            ..lineTo(88, 46)
            ..lineTo(80, 48)
            ..close(),
          Paint()..color = const Color(0xFFE5A843),
        );
        final legs = Paint()
          ..color = const Color(0xFF765335)
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(const Offset(58, 56), const Offset(57, 63), legs);
        canvas.drawLine(const Offset(68, 56), const Offset(69, 63), legs);
      } else {
        final bodyRect = name.contains('giraffe')
            ? const Rect.fromLTRB(52, 43, 77, 57)
            : const Rect.fromLTRB(49, 43, 76, 59);
        canvas.drawOval(
          bodyRect,
          Paint()
            ..shader = ui.Gradient.linear(
              const Offset(51, 43),
              const Offset(75, 60),
              [Color.lerp(animalColor, Colors.white, 0.3)!, animalColor],
            ),
        );
        if (name.contains('giraffe')) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTRB(68, 31, 75, 48),
              const Radius.circular(3),
            ),
            Paint()..color = animalColor,
          );
          canvas.drawCircle(
            const Offset(74, 31),
            5.5,
            Paint()..color = animalColor,
          );
          for (final spot in const [
            Offset(57, 47),
            Offset(66, 53),
            Offset(72, 39),
          ]) {
            canvas.drawCircle(
              spot,
              2,
              Paint()..color = const Color(0xFFAA7134),
            );
          }
        } else if (name.contains('elephant')) {
          canvas.drawCircle(
            const Offset(75, 46),
            8,
            Paint()..color = animalColor,
          );
          canvas.drawOval(
            Rect.fromCenter(center: const Offset(82, 50), width: 6, height: 12),
            Paint()..color = const Color(0xFF71858A),
          );
          canvas.drawLine(
            const Offset(80, 49),
            const Offset(83, 58),
            Paint()
              ..color = animalColor
              ..strokeWidth = 4
              ..strokeCap = StrokeCap.round,
          );
        } else {
          canvas.drawCircle(
            const Offset(75, 45),
            7,
            Paint()..color = animalColor,
          );
          canvas.drawCircle(
            const Offset(71, 39),
            3.5,
            Paint()..color = Color.lerp(animalColor, Colors.white, 0.15)!,
          );
          canvas.drawCircle(
            const Offset(80, 39),
            3.5,
            Paint()..color = Color.lerp(animalColor, Colors.white, 0.15)!,
          );
        }
        canvas.drawCircle(
          const Offset(77, 44),
          1.5,
          Paint()..color = const Color(0xFF26332B),
        );
        if (name.contains('tiger')) {
          final stripePaint = Paint()
            ..color = const Color(0xFF49352A)
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(
            const Offset(55, 45),
            const Offset(58, 51),
            stripePaint,
          );
          canvas.drawLine(
            const Offset(63, 44),
            const Offset(66, 50),
            stripePaint,
          );
          canvas.drawLine(
            const Offset(69, 48),
            const Offset(71, 54),
            stripePaint,
          );
        }
        final legs = Paint()
          ..color = Color.lerp(animalColor, Colors.black, 0.18)!
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        for (final x in const [55.0, 70.0]) {
          canvas.drawLine(Offset(x, 55), Offset(x - 1, 62), legs);
        }
        canvas.drawLine(
          const Offset(50, 47),
          const Offset(45, 43),
          Paint()
            ..color = animalColor
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // The low front rail keeps the animal visible while making the habitat feel enclosed.
    final frontFence = Paint()
      ..color = const Color(0xFF9B6C43)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      ui.Path()
        ..moveTo(23, 54)
        ..lineTo(64, 76)
        ..lineTo(105, 54),
      frontFence,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ZooEnclosurePainter oldDelegate) =>
      oldDelegate.animalName != animalName ||
      oldDelegate.includeAnimal != includeAnimal;
}

class ZooMapPinPainter extends CustomPainter {
  final String category;

  const ZooMapPinPainter(this.category);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 76);

    final color = switch (category.toLowerCase()) {
      'animal' => const Color(0xFF398764),
      'facility' => const Color(0xFFE58A3A),
      _ => const Color(0xFF4B87A0),
    };
    final pin = ui.Path()
      ..moveTo(32, 72)
      ..cubicTo(25, 60, 9, 44, 9, 27)
      ..cubicTo(9, 14, 19, 5, 32, 5)
      ..cubicTo(45, 5, 55, 14, 55, 27)
      ..cubicTo(55, 44, 39, 60, 32, 72)
      ..close();

    canvas.drawShadow(pin, const Color(0x6623332B), 4, true);
    canvas.drawPath(
      pin,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(14, 8),
          const Offset(48, 66),
          [Color.lerp(color, Colors.white, 0.18)!, color],
        ),
    );
    canvas.drawPath(
      pin,
      Paint()
        ..color = const Color(0xFFFFFEF8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(const Offset(32, 27), 16, Paint()..color = Colors.white);

    final detailPaint = Paint()
      ..color = Color.lerp(color, const Color(0xFF243C2D), 0.26)!
      ..style = PaintingStyle.fill;
    if (category.toLowerCase() == 'animal') {
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(32, 31), width: 15, height: 11),
        detailPaint,
      );
      for (final point in const [
        Offset(22.5, 23),
        Offset(28.5, 19),
        Offset(35.5, 19),
        Offset(41.5, 23),
      ]) {
        canvas.drawCircle(point, 3.2, detailPaint);
      }
    } else if (category.toLowerCase() == 'facility') {
      final roof = ui.Path()
        ..moveTo(20, 26)
        ..lineTo(32, 18)
        ..lineTo(44, 26)
        ..close();
      canvas.drawPath(roof, detailPaint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(22, 25, 42, 37),
          const Radius.circular(2),
        ),
        detailPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTRB(29, 29, 35, 37),
          const Radius.circular(1.5),
        ),
        Paint()..color = Colors.white,
      );
    } else {
      final star = ui.Path();
      for (var point = 0; point < 10; point++) {
        final angle = -math.pi / 2 + point * math.pi / 5;
        final radius = point.isEven ? 11.0 : 5.2;
        final position = Offset(
          32 + radius * math.cos(angle),
          27 + radius * math.sin(angle),
        );
        if (point == 0) {
          star.moveTo(position.dx, position.dy);
        } else {
          star.lineTo(position.dx, position.dy);
        }
      }
      star.close();
      canvas.drawPath(star, detailPaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ZooMapPinPainter oldDelegate) =>
      oldDelegate.category != category;
}

class ZooMapData {
  final List<ZooWaypoint> waypoints;
  final List<List<LatLng>> routes;

  const ZooMapData({required this.waypoints, required this.routes});
}
