import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class OnboardingAudioService {
  static final OnboardingAudioService _instance =
      OnboardingAudioService._internal();
  factory OnboardingAudioService() => _instance;
  OnboardingAudioService._internal();

  late AudioPlayer _audioPlayer;
  bool _isInitialized = false;
  bool _isPlaying = false;

  // Audio file path
  static const String _audioAsset = 'audio/chumbucket.mp3';

  // Initialize the audio player
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _audioPlayer = AudioPlayer();

      // Set up audio player configurations
      await _audioPlayer.setReleaseMode(ReleaseMode.loop); // Loop the audio
      await _audioPlayer.setVolume(0.6); // Set moderate volume

      _isInitialized = true;

      if (kDebugMode) {
        print('OnboardingAudioService initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing OnboardingAudioService: $e');
      }
    }
  }

  // Start playing the onboarding background music
  Future<void> startOnboardingMusic() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isPlaying) return; // Already playing

    try {
      await _audioPlayer.play(AssetSource(_audioAsset));
      _isPlaying = true;

      // Listen for completion to restart if needed
      _audioPlayer.onPlayerComplete.listen((event) {
        _isPlaying = false;
        // Restart the audio if still needed
        if (_isPlaying) {
          startOnboardingMusic();
        }
      });

      if (kDebugMode) {
        print('Onboarding music started');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error starting onboarding music: $e');
      }
    }
  }

  // Stop the onboarding background music
  Future<void> stopOnboardingMusic() async {
    if (!_isInitialized || !_isPlaying) return;

    try {
      await _audioPlayer.stop();
      _isPlaying = false;

      if (kDebugMode) {
        print('Onboarding music stopped');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error stopping onboarding music: $e');
      }
    }
  }

  // Pause the music (can be resumed)
  Future<void> pauseOnboardingMusic() async {
    if (!_isInitialized || !_isPlaying) return;

    try {
      await _audioPlayer.pause();
      _isPlaying = false;

      if (kDebugMode) {
        print('Onboarding music paused');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error pausing onboarding music: $e');
      }
    }
  }

  // Resume the music
  Future<void> resumeOnboardingMusic() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isPlaying) return;

    try {
      await _audioPlayer.resume();
      _isPlaying = true;

      if (kDebugMode) {
        print('Onboarding music resumed');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error resuming onboarding music: $e');
      }
    }
  }

  // Get current playing state
  bool get isPlaying => _isPlaying;

  // Dispose the audio player
  Future<void> dispose() async {
    if (!_isInitialized) return;

    try {
      await _audioPlayer.stop();
      await _audioPlayer.dispose();
      _isPlaying = false;
      _isInitialized = false;

      if (kDebugMode) {
        print('OnboardingAudioService disposed');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error disposing OnboardingAudioService: $e');
      }
    }
  }
}
