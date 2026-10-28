import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../models/zoo_waypoint.dart';
import '../services/gamification_service.dart';

class AnimalDiscoveryAction extends StatefulWidget {
  final ZooWaypoint waypoint;
  final GamificationService service;
  final bool isReady;
  final bool alreadyDiscovered;
  final ValueChanged<DiscoveryResult> onResult;

  const AnimalDiscoveryAction({
    super.key,
    required this.waypoint,
    required this.service,
    required this.isReady,
    required this.alreadyDiscovered,
    required this.onResult,
  });

  @override
  State<AnimalDiscoveryAction> createState() => _AnimalDiscoveryActionState();
}

class _AnimalDiscoveryActionState extends State<AnimalDiscoveryAction> {
  bool _isLoading = false;
  bool _discoveredHere = false;

  bool get _isDiscovered => widget.alreadyDiscovered || _discoveredHere;

  Future<void> _discover({bool debugSimulation = false}) async {
    if (_isLoading || _isDiscovered) return;
    setState(() => _isLoading = true);
    final result = debugSimulation
        ? await widget.service.debugDiscoverNearby(widget.waypoint)
        : await widget.service.discoverAnimal(widget.waypoint);
    widget.onResult(result);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _discoveredHere = result.wasDiscovered;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (!widget.service.rules.isEligible(widget.waypoint)) {
      return Text(
        'This animal is not eligible under the current discovery rules.',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: colors.onSurfaceVariant),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Discover from permitted visitor areas only. Never cross barriers or disturb animals.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: !widget.isReady || _isLoading || _isDiscovered
                ? null
                : _discover,
            icon: _isLoading
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _isDiscovered
                        ? Icons.check_circle_rounded
                        : Icons.explore_rounded,
                  ),
            label: Text(
              _isDiscovered
                  ? 'Discovered - +${widget.service.profile.discoveries[widget.waypoint.id]?.xpAwarded ?? widget.service.rules.xpPerDiscovery} XP'
                  : _isLoading
                  ? 'Checking your location...'
                  : 'Explore this animal - +${widget.service.rules.xpPerDiscovery} XP',
            ),
          ),
        ),
        if (kDebugMode && widget.isReady && !_isDiscovered)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _isLoading
                  ? null
                  : () => _discover(debugSimulation: true),
              icon: const Icon(Icons.bug_report_outlined, size: 17),
              label: const Text('DEBUG: simulate nearby discovery'),
            ),
          ),
      ],
    );
  }
}
