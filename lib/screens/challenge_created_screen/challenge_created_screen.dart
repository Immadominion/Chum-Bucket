import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/models/models.dart';
import 'package:chumbucket/screens/create_challenge_screen/widgets/action_button.dart';
import 'package:rive/rive.dart';

class ChallengeStateScreen extends StatefulWidget {
  final ChallengeStatus status;
  final String? errorMessage;
  final VoidCallback onDone;

  const ChallengeStateScreen({
    super.key,
    required this.status,
    this.errorMessage,
    required this.onDone,
  });

  @override
  State<ChallengeStateScreen> createState() => _ChallengeStateScreenState();
}

class _ChallengeStateScreenState extends State<ChallengeStateScreen> {
  Artboard? _riveArtboard;
  bool _isRiveLoaded = false;
  StateMachineController? _controller;
  SMITrigger? _failTrigger;
  SMITrigger? _successTrigger;
  SMITrigger? _pendingTrigger;

  @override
  void initState() {
    super.initState();
    // Load the animation file when the widget initializes
    _loadRiveFile();
  }

  // Add this method to load the Rive file directly
  void _loadRiveFile() async {
    try {
      print("Starting to load Rive file...");
      final data = await rootBundle.load(
        'assets/animations/Loading-animation.riv',
      );
      print("File loaded from assets");

      final file = RiveFile.import(data);
      print("Rive file imported");

      final artboard = file.mainArtboard;
      print("Artboard accessed: ${artboard.name}");

      // Print available state machines for debugging
      if (artboard.stateMachines.isNotEmpty) {
        print("Available state machines:");
        for (final machine in artboard.stateMachines) {
          print(" - '${machine.name}'");
        }
      } else {
        print("No state machines found in this artboard!");
      }

      // Try different variations of the state machine name
      final possibleNames = [
        'fetching status',
        'Fetching status',
        'state_machine',
        'state machine',
        'StateMachine',
        'default',
      ];

      for (final machineName in possibleNames) {
        print("Trying to load state machine: '$machineName'");
        try {
          _controller = StateMachineController.fromArtboard(
            artboard,
            machineName,
          );
          if (_controller != null) {
            print("Successfully loaded state machine: '$machineName'");
            artboard.addController(_controller!);

            // Get the state machine inputs
            _failTrigger = _controller!.findSMI('Fetch failed');
            _successTrigger = _controller!.findSMI('Fetch succesful');
            _pendingTrigger = _controller!.findSMI('pending');

            print(
              "Input triggers found: fail=${_failTrigger != null}, success=${_successTrigger != null}, pending=${_pendingTrigger != null}",
            );
            break;
          }
        } catch (e) {
          print("Error loading state machine '$machineName': $e");
        }
      }

      if (_controller == null) {
        print("Failed to load any state machine controller!");
      } else {
        // Immediately trigger the appropriate animation
        _triggerAnimation();
      }

      setState(() {
        _riveArtboard = artboard;
        _isRiveLoaded = true;
      });
    } catch (e) {
      print('Rive file loading error: $e');
      setState(() {
        _isRiveLoaded = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _triggerAnimation() {
    if (_controller == null) return;

    switch (widget.status) {
      case ChallengeStatus.accepted:
      case ChallengeStatus.completed:
        _successTrigger?.fire();
        break;
      case ChallengeStatus.failed:
      case ChallengeStatus.cancelled:
        _failTrigger?.fire();
        break;
      case ChallengeStatus.pending:
      default:
        _pendingTrigger?.fire();
        break;
    }
  }

  void _onRiveInit(Artboard artboard) {
    _controller = StateMachineController.fromArtboard(
      artboard,
      'Fetching status',
    );
    if (_controller != null) {
      artboard.addController(_controller!);
      _failTrigger = _controller!.findSMI('Fetching failed');
      _successTrigger = _controller!.findSMI('Fetching successful');
      _pendingTrigger = _controller!.findSMI('pending');

      // Trigger the appropriate animation based on status
      _triggerAnimation();
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusData = _getStatusData(widget.status);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Challenge Status"),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              color: Colors.transparent,
              height: 200.h,
              width: 200.h,
              child: _buildAnimation(context),
            ),
            const SizedBox(height: 32),
            Text(
              statusData.title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: statusData.color,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              statusData.message,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            if (widget.status == ChallengeStatus.failed &&
                widget.errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                widget.errorMessage!,
                style: TextStyle(color: Colors.red.shade400),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 32),
            ActionButton(
              text: "Return to Home",
              isLoading: false,
              onPressed:
                  () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
              description: statusData.buttonDescription,
              isSecondStep: true,
            ),
          ],
        ),
      ),
    );
  }

  _ChallengeStatusData _getStatusData(ChallengeStatus status) {
    switch (status) {
      case ChallengeStatus.accepted:
        return _ChallengeStatusData(
          title: "Challenge Created!",
          message: "Your challenge has been created successfully.",
          color: Colors.green,
          buttonDescription: "Your challenge is ready to go",
        );
      case ChallengeStatus.pending:
        return _ChallengeStatusData(
          title: "Creating Challenge...",
          message:
              "We're processing your request. This might take a few seconds.",
          color: Colors.amber,
          buttonDescription: "Processing your challenge",
        );
      case ChallengeStatus.failed:
        return _ChallengeStatusData(
          title: "Challenge Failed",
          message:
              "Something went wrong. Coins have been refunded to both users.",
          color: Colors.red,
          buttonDescription: "Challenge could not be created",
        );
      case ChallengeStatus.completed:
        return _ChallengeStatusData(
          title: "Challenge Completed",
          message: "This challenge has been completed.",
          color: Colors.blue,
          buttonDescription: "Congratulations on completing",
        );
      case ChallengeStatus.cancelled:
        return _ChallengeStatusData(
          title: "Challenge Cancelled",
          message: "This challenge has been cancelled.",
          color: Colors.orange,
          buttonDescription: "Challenge has been cancelled",
        );
    }
  }

  Widget _buildAnimation(BuildContext context) {
    if (_isRiveLoaded && _riveArtboard != null) {
      // Set the artboard background to transparent
      // _riveArtboard!.co = Colors.transparent;

      return Container(
        // Using constraints to make it responsive
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.of(context).size.height * 0.4, // 40% of screen height
          maxWidth:
              MediaQuery.of(context).size.width * 0.8, // 80% of screen width
        ),
        child: Rive(
          artboard: _riveArtboard!,
          fit: BoxFit.contain, // Try different BoxFit values
          alignment: Alignment.center,
        ),
      );
    } else {
      return _buildFallbackAnimation();
    }
  }

  Widget _buildFallbackAnimation() {
    // Fallback animations based on status
    switch (widget.status) {
      case ChallengeStatus.accepted:
      case ChallengeStatus.completed:
        return _buildStatusAnimation(
          Icons.check_circle_outline_rounded,
          Colors.green,
          true,
        );
      case ChallengeStatus.failed:
      case ChallengeStatus.cancelled:
        return _buildStatusAnimation(Icons.cancel_outlined, Colors.red, false);
      case ChallengeStatus.pending:
        return _buildStatusAnimation(Icons.hourglass_top, Colors.amber, true);
    }
  }

  Widget _buildStatusAnimation(IconData icon, Color color, bool animated) {
    return Center(
      child:
          animated
              ? TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: 0.8 + (value * 0.2),
                    child: Opacity(
                      opacity: value,
                      child: Icon(icon, size: 120, color: color),
                    ),
                  );
                },
                curve: Curves.elasticOut,
              )
              : Icon(icon, size: 120, color: color),
    );
  }
}

class _ChallengeStatusData {
  final String title;
  final String message;
  final Color color;
  final String buttonDescription;

  _ChallengeStatusData({
    required this.title,
    required this.message,
    required this.color,
    required this.buttonDescription,
  });
}
