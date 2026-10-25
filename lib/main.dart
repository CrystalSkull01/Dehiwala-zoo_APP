import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

void main() {
  runApp(const ZooMapApp());
}

class ZooMapApp extends StatelessWidget {
  const ZooMapApp({super.key, this.startIn3dMode = true});

  final bool startIn3dMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dehiwala Zoo Map',
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
      home: ZooMapScreen(startIn3dMode: startIn3dMode),
    );
  }
}

class ZooMapScreen extends StatefulWidget {
  const ZooMapScreen({super.key, this.startIn3dMode = true});

  final bool startIn3dMode;

  @override
  State<ZooMapScreen> createState() => _ZooMapScreenState();
}

class _ZooMapScreenState extends State<ZooMapScreen> {
  late final Future<ZooMapData> _mapDataFuture;

  // Controls the position and zoom of the map.
  final MapController _mapController = MapController();

  // Stores the visitor's most recently retrieved position.
  LatLng? _currentPosition;

  // Prevents repeated location requests while one is running.
  bool _isLocating = false;
  bool _isSearchExpanded = false;
  int _selectedTab = 0;
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<List<ZooWaypoint>> _visibleWaypoints =
      ValueNotifier<List<ZooWaypoint>>([]);
  List<ZooWaypoint> _allWaypoints = const [];
  Map<String, AnimalPhoto> _animalPhotos = const {};
  String _selectedAnimalGroup = 'All';
  String _selectedCategory = 'All';
  late final bool _is3dMode;
  maplibre.MapLibreMapController? _mapLibreController;
  bool _mapLibreStyleReady = false;
  LatLng? _pendingMapTarget;
  double _pendingMapZoom = 17;
  ZooMapExtent? _zooMapExtent;

  static const _mapLibreStyle = 'https://tiles.openfreemap.org/styles/liberty';
  static const _waypointSourceId = 'zoo-waypoints';
  static const _routeSourceId = 'zoo-routes';
  static const _visitorSourceId = 'visitor-location';

  static const _categories = ['All', 'Animals', 'Facilities'];

  AnimalPhoto? _photoFor(ZooWaypoint waypoint) => _animalPhotos[waypoint.id];

  String _animalGroup(String name) {
    final species = name.replaceFirst(RegExp(r'\s+\d+$'), '').split('/').first.trim();
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
    _mapDataFuture = _loadMapData();
    _searchController.addListener(_onSearchChanged);
    _visibleWaypoints.addListener(_onVisibleWaypointsChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    _visibleWaypoints.removeListener(_onVisibleWaypointsChanged);
    _visibleWaypoints.dispose();
    super.dispose();
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
    return waypoints.where((waypoint) {
      final matchesCategory = switch (_selectedCategory) {
        'Animals' => waypoint.category.toLowerCase() == 'animal',
        'Facilities' => waypoint.category.toLowerCase() == 'facility',
        _ => true,
      };
      return matchesCategory &&
          (query.isEmpty || waypoint.name.toLowerCase().contains(query));
    }).toList();
  }

  void _selectWaypoint(ZooWaypoint waypoint) {
    FocusScope.of(context).unfocus();
    _selectedCategory = 'All';
    _searchController.clear();
    setState(() {
      _isSearchExpanded = false;
    });
    _moveMapTo(LatLng(waypoint.latitude, waypoint.longitude), 18);
    _showWaypointDetails(waypoint);
  }

  void _openWaypointFromDirectory(ZooWaypoint waypoint) {
    FocusScope.of(context).unfocus();
    _selectedCategory = 'All';
    _searchController.clear();
    setState(() {
      _selectedTab = 0;
      _isSearchExpanded = false;
    });
    _moveMapTo(LatLng(waypoint.latitude, waypoint.longitude), 18);
    _showWaypointDetails(waypoint);
  }

  void _selectTab(int index) {
    FocusScope.of(context).unfocus();
    if (index != 0) {
      _searchController.clear();
      _isSearchExpanded = false;
    }
    setState(() => _selectedTab = index);
  }

  Widget _buildDirectory(ZooMapData data, String category) {
    final allLocations = data.waypoints
        .where((waypoint) => waypoint.category.toLowerCase() == category)
        .toList()
      ..sort((first, second) => first.name.compareTo(second.name));
    final locations = category == 'animal' && _selectedAnimalGroup != 'All'
        ? allLocations.where((waypoint) => _animalGroup(waypoint.name) == _selectedAnimalGroup).toList()
        : allLocations;
    final title = category == 'animal' ? 'Animals' : 'Facilities';
    final colors = Theme.of(context).colorScheme;

    final featuredAnimals = category == 'animal'
        ? locations.where((waypoint) => _photoFor(waypoint) != null).take(8).toList()
        : const <ZooWaypoint>[];

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
                  Text(title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(category == 'animal' ? 'Discover the wildlife at Dehiwala Zoo' : 'Everything you need for an easy visit', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(20)),
              child: Text('${locations.length} ${category == 'animal' ? 'animals' : 'places'}', style: TextStyle(color: colors.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ],
        ),
        if (category == 'animal') ...[
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final group in const ['All', 'Mammals', 'Birds']) ...[
                  if (group != 'All') const SizedBox(width: 8),
                  FilterChip(
                    label: Text(group),
                    selected: _selectedAnimalGroup == group,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _selectedAnimalGroup = group),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (featuredAnimals.isNotEmpty) ...[
          Text('Featured wildlife', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: featuredAnimals.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final waypoint = featuredAnimals[index];
                return _buildFeaturedAnimalCard(waypoint);
              },
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(category == 'animal' ? (_selectedAnimalGroup == 'All' ? 'All animals' : _selectedAnimalGroup) : 'Zoo facilities', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        for (final waypoint in locations)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Card(
              color: colors.surface,
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.45))),
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
                leading: _buildWaypointThumbnail(waypoint),
                title: Text(waypoint.name, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(waypoint.needsReview ? 'Name needs verification' : category == 'animal' ? 'Animal habitat' : 'Visitor facility'),
                trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: colors.onSurfaceVariant),
                onTap: () => _openWaypointFromDirectory(waypoint),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWaypointThumbnail(ZooWaypoint waypoint) {
    final photo = _photoFor(waypoint);
    if (photo != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: SizedBox(
          width: 54,
          height: 54,
          child: _buildPhotoImage(photo, width: 54, height: 54),
        ),
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

  Widget _buildPhotoImage(
    AnimalPhoto photo, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    Widget failedImage() => Container(
      width: width,
      height: height,
      color: const Color(0xFFE1E8DC),
      child: const Icon(Icons.pets_rounded, size: 36),
    );

    if (photo.assetPath != null) {
      return Image.asset(
        photo.assetPath!,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => failedImage(),
      );
    }
    return Image.network(
      photo.url,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Container(width: width, height: height, color: const Color(0xFFE1E8DC)),
      errorBuilder: (_, _, _) => failedImage(),
    );
  }

  Widget _buildFeaturedAnimalCard(ZooWaypoint waypoint) {
    final photo = _photoFor(waypoint)!;
    return Semantics(
      button: true,
      label: 'Show ${waypoint.name} on the map',
      child: GestureDetector(
        onTap: () => _openWaypointFromDirectory(waypoint),
        child: SizedBox(
          width: 260,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildPhotoImage(photo),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xCC101910)], stops: [0.42, 1]),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 14,
                  bottom: 14,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(waypoint.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 3),
                  Text('Photo by ${photo.author} | Reference image', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_outward_rounded, color: Colors.white, size: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
        mapController.animateCamera(
          maplibre.CameraUpdate.newCameraPosition(
            maplibre.CameraPosition(
              target: maplibre.LatLng(point.latitude, point.longitude),
              zoom: zoom,
              tilt: 55,
              bearing: 20,
            ),
          ),
          duration: const Duration(milliseconds: 850),
        ).then<void>((_) {}).catchError((Object error) {
          debugPrint('Could not animate 3D map camera: $error');
        }),
      );
      return;
    }
    _mapController.move(point, zoom);
  }

  Map<String, dynamic> _waypointsGeoJson(List<ZooWaypoint> waypoints) => {
    'type': 'FeatureCollection',
    'features': waypoints.map((waypoint) {
      return {
        'type': 'Feature',
        'id': waypoint.id,
        'properties': {
          'id': waypoint.id,
          'name': waypoint.name,
          'category': waypoint.category.toLowerCase(),
        },
        'geometry': {
          'type': 'Point',
          'coordinates': [waypoint.longitude, waypoint.latitude],
        },
      };
    }).toList(),
  };

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

  Map<String, dynamic> _visitorGeoJson(LatLng point) => {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'id': 'visitor',
        'properties': const <String, dynamic>{},
        'geometry': {
          'type': 'Point',
          'coordinates': [point.longitude, point.latitude],
        },
      },
    ],
  };

  Future<void> _onMapLibreStyleLoaded(ZooMapData data) async {
    final controller = _mapLibreController;
    if (controller == null) return;

    try {
      await controller.addGeoJsonSource(
        _routeSourceId,
        _routesGeoJson(data.routes),
      );
      await controller.addLineLayer(
        _routeSourceId,
        'zoo-route-lines',
        const maplibre.LineLayerProperties(
          lineColor: '#438565',
          lineWidth: 3.5,
          lineOpacity: 0.9,
        ),
      );
      await controller.addGeoJsonSource(
        _waypointSourceId,
        _waypointsGeoJson(_visibleWaypoints.value),
      );
      await controller.addCircleLayer(
        _waypointSourceId,
        'zoo-location-points',
        const maplibre.CircleLayerProperties(
          circleRadius: 9,
          circleColor: [
            'match',
            ['get', 'category'],
            'animal',
            '#388454',
            'facility',
            '#D87932',
            '#596875',
          ],
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2.5,
        ),
      );
      await controller.addGeoJsonSource(
        _visitorSourceId,
        _currentPosition == null
            ? _emptyGeoJson
            : _visitorGeoJson(_currentPosition!),
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
      _showMessage('Could not load the 3D map. Check your internet connection.');
    }
  }

  static const _emptyGeoJson = <String, dynamic>{
    'type': 'FeatureCollection',
    'features': <dynamic>[],
  };

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
      styleString: _mapLibreStyle,
      initialCameraPosition: const maplibre.CameraPosition(
        target: maplibre.LatLng(6.8565, 79.8728),
        zoom: 17,
        tilt: 55,
        bearing: 20,
      ),
      cameraTargetBounds: maplibre.CameraTargetBounds(
        maplibre.LatLngBounds(
          southwest: maplibre.LatLng(extent.south, extent.west),
          northeast: maplibre.LatLng(extent.north, extent.east),
        ),
      ),
      minMaxZoomPreference: const maplibre.MinMaxZoomPreference(17, 20),
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: true,
      zoomGesturesEnabled: true,
      scrollGesturesEnabled: true,
      featureTapsTriggersMapClick: true,
      logoEnabled: false,
      attributionButtonPosition: maplibre.AttributionButtonPosition.bottomRight,
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
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Find animals or facilities',
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
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final category in _categories)
                      FilterChip(
                        label: Text(category),
                        selected: _selectedCategory == category,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          _selectedCategory = category;
                          _updateFilteredWaypoints();
                        },
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '${matches.length} places',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
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
                                      leading: CircleAvatar(
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
                                      subtitle: Text(waypoint.category),
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
      rootBundle.loadString('assets/data/animal_photo_credits.json'),
    ]);

    final photoEntries = jsonDecode(files[2]) as List<dynamic>;
    _animalPhotos = {
      for (final item in photoEntries)
        (item as Map<String, dynamic>)['id'] as String:
            AnimalPhoto.fromJson(item['photo'] as Map<String, dynamic>),
    };

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
  Future<void> _locateMe() async {
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
          _showMessage('Could not get a location fix. Check GPS and try again.');
          return;
        }
      }

      if (!mounted) return;

      final point = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentPosition = point;
      });

      // Centre the active map on the visitor and update its location marker.
      _moveMapTo(point, 18);
      final mapLibreController = _mapLibreController;
      if (_is3dMode && mapLibreController != null && _mapLibreStyleReady) {
        unawaited(
          mapLibreController
              .setGeoJsonSource(_visitorSourceId, _visitorGeoJson(point))
              .catchError((Object error) {
                debugPrint('Could not update visitor location: $error');
              }),
        );
      }
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

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showPhotoCredits(AnimalPhoto photo) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Photo credits'),
        content: SingleChildScrollView(
          child: SelectableText(
            'Photo: ${photo.title}\n\n'
            'Author: ${photo.author}\n\n'
            'Source: ${photo.sourceUrl}\n\n'
            'License: ${photo.license}\n'
            '${photo.licenseUrl}',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
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
                if (_photoFor(waypoint) case final photo?)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildPhotoImage(photo),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Color(0xCC101910)],
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
                                Text(waypoint.name, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 3),
                                Text('Reference photo by ${photo.author}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
                      backgroundColor: _markerColor(
                        waypoint.category,
                      ).withValues(alpha: 0.12),
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
                            style: Theme.of(sheetContext).textTheme.bodyMedium
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_photoFor(waypoint) case final photo?) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _showPhotoCredits(photo),
                      icon: const Icon(Icons.info_outline_rounded, size: 18),
                      label: Text('${photo.license} | Photo credits'),
                    ),
                  ),
                ],
                if (waypoint.needsReview) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.tertiaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'This location name needs verification.',
                      style: TextStyle(
                        color: colors.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                if (waypoint.reviewNote != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    waypoint.reviewNote!,
                    style: Theme.of(sheetContext).textTheme.bodyMedium,
                  ),
                ],
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sectionSubtitle = switch (_selectedTab) {
      1 => 'Meet the animals',
      2 => 'Find zoo facilities',
      _ => 'Explore the zoo',
    };
    return Scaffold(
      appBar: AppBar(
        backgroundColor: colors.surface,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.pets_rounded, color: colors.primary, size: 21),
            ),
            const SizedBox(width: 11),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dehiwala Zoo'),
                Text(
                  sectionSubtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: FutureBuilder<ZooMapData>(
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
          _zooMapExtent ??= _boundsFor(data);
          if (_allWaypoints.isEmpty && data.waypoints.isNotEmpty) {
            _allWaypoints = data.waypoints;
            _visibleWaypoints.value = _filterWaypoints(_allWaypoints);
          }

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
                  cameraConstraint: CameraConstraint.containCenter(
                    bounds: LatLngBounds(
                      LatLng(_zooMapExtent!.south, _zooMapExtent!.west),
                      LatLng(_zooMapExtent!.north, _zooMapExtent!.east),
                    ),
                  ),
                ),
                children: [
              // Geographic map background.
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/'
                    '{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.dehiwala_zoo_app',
              ),

              // Recorded GPS track. Each segment stays separate.
              PolylineLayer(
                    simplificationTolerance: 1,
                polylines: data.routes.map((route) {
                  return Polyline(
                    points: route,
                    color: const Color(0xFF438565),
                    strokeWidth: 4,
                  );
                }).toList(),
              ),

              // Named animal and facility locations.
                  ValueListenableBuilder<List<ZooWaypoint>>(
                    valueListenable: _visibleWaypoints,
                    builder: (context, waypoints, _) => MarkerLayer(
                      markers: waypoints.map((waypoint) {
                        return Marker(
                          point: LatLng(waypoint.latitude, waypoint.longitude),
                          width: 48,
                          height: 48,
                          child: Semantics(
                            button: true,
                            label: waypoint.name,
                            child: GestureDetector(
                              onTap: () => _showWaypointDetails(waypoint),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _markerColor(waypoint.category),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: Icon(
                                  _markerIcon(waypoint.category),
                                  color: Colors.white,
                                  size: 23,
                                ),
                          ),
                        ),
                      ),
                        );
                      }).toList(),
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
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
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
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),

              // Required OpenStreetMap attribution.
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
                ],
              ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: _buildMapSearch(),
              ),
            ],
          );
          return IndexedStack(
            index: _selectedTab,
            children: [
              mapPage,
              _buildDirectory(data, 'animal'),
              _buildDirectory(data, 'facility'),
            ],
          );
        },
      ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: _selectTab,
        backgroundColor: colors.surface,
        indicatorColor: colors.primaryContainer,
        destinations: const [
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
        ],
      ),

      // Button to retrieve and display the visitor's location.
      floatingActionButton: _selectedTab == 0
          ? FloatingActionButton.extended(
        onPressed: _isLocating ? null : _locateMe,
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
            : const Icon(Icons.my_location),
        label: Text(_isLocating ? 'Locating...' : 'Locate Me'),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }
}

typedef ZooMapExtent = ({double south, double west, double north, double east});

class AnimalPhoto {
  final String url;
  final String? assetPath;
  final String title;
  final String author;
  final String sourceUrl;
  final String license;
  final String licenseUrl;

  const AnimalPhoto({
    required this.url,
    this.assetPath,
    required this.title,
    required this.author,
    required this.sourceUrl,
    required this.license,
    required this.licenseUrl,
  });

  factory AnimalPhoto.fromJson(Map<String, dynamic> json) => AnimalPhoto(
    url: json['url'] as String,
    assetPath: json['assetPath'] as String?,
    title: json['title'] as String,
    author: json['author'] as String,
    sourceUrl: json['sourceUrl'] as String,
    license: json['license'] as String,
    licenseUrl: json['licenseUrl'] as String,
  );
}

class ZooMapData {
  final List<ZooWaypoint> waypoints;
  final List<List<LatLng>> routes;

  const ZooMapData({required this.waypoints, required this.routes});
}

class ZooWaypoint {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String category;
  final bool needsReview;
  final String? reviewNote;

  const ZooWaypoint({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.category,
    required this.needsReview,
    this.reviewNote,
  });

  factory ZooWaypoint.fromJson(Map<String, dynamic> json) {
    return ZooWaypoint(
      id: json['id'] as String? ?? 'unknown',
      name: json['name'] as String? ?? 'Unnamed location',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      category: json['category'] as String? ?? 'other',
      needsReview: json['needsReview'] as bool? ?? false,
      reviewNote: json['reviewNote'] as String?,
    );
  }
}
