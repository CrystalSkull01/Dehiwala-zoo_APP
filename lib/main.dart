import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const ZooMapApp());
}

class ZooMapApp extends StatelessWidget {
  const ZooMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dehiwala Zoo Map',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const ZooMapScreen(),
    );
  }
}

class ZooMapScreen extends StatefulWidget {
  const ZooMapScreen({super.key});

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

  @override
  void initState() {
    super.initState();
    _mapDataFuture = _loadMapData();
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

      // Centre the map on the visitor.
      _mapController.move(point, 18);
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
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  waypoint.name,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text('ID: ${waypoint.id}'),
                Text('Category: ${waypoint.category}'),
                Text(
                  'Latitude: '
                  '${waypoint.latitude.toStringAsFixed(6)}',
                ),
                Text(
                  'Longitude: '
                  '${waypoint.longitude.toStringAsFixed(6)}',
                ),
                if (waypoint.needsReview) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'This location name needs verification.',
                    style: TextStyle(
                      color: Colors.deepOrange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                if (waypoint.reviewNote != null) ...[
                  if (!waypoint.needsReview) const SizedBox(height: 12),
                  Text(waypoint.reviewNote!),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dehiwala Zoo Map'), centerTitle: true),
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

          return FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(6.8565, 79.8728),
              initialZoom: 17,
              minZoom: 12,
              maxZoom: 19,
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
                polylines: data.routes.map((route) {
                  return Polyline(
                    points: route,
                    color: Colors.blue,
                    strokeWidth: 4,
                  );
                }).toList(),
              ),

              // Named animal and facility locations.
              MarkerLayer(
                markers: data.waypoints.map((waypoint) {
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
          );
        },
      ),

      // Button to retrieve and display the visitor's location.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLocating ? null : _locateMe,
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
      ),
    );
  }
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
