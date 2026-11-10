import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_dimens.dart';
import '../widgets/ar_overlay_image.dart';
import '../widgets/bottom_controls.dart';
import '../widgets/camera_placeholder.dart';
import '../widgets/feedback_prompter.dart';

/// The AR tracing surface: the chosen overlay ([imagePath] or [presetSvgUrl])
/// shown **centred** over the live camera, with opacity / camera / flash
/// controls. Pushed from [ArHomeScreen] once a photo is chosen; a single
/// floating Home button (top-left) pops back to the chooser.
class ArDrawingScreen extends StatefulWidget {
  const ArDrawingScreen({super.key, this.imagePath, this.presetSvgUrl});

  /// Device photo or SVG file path chosen in the AR home; null for a preset.
  final String? imagePath;

  /// Public URL of a portal preset SVG; null when a device file is used.
  final String? presetSvgUrl;

  @override
  State<ArDrawingScreen> createState() => _ArDrawingScreenState();
}

class _ArDrawingScreenState extends State<ArDrawingScreen>
    with WidgetsBindingObserver {
  double _opacity = 0.6;
  bool _isLocked = false;
  bool _flashlightOn = false;
  CameraController? _cameraController;
  bool _camerasLoading = true;
  bool _disposed = false;
  String? _cameraError;
  int _currentCameraIndex = 0;
  List<CameraDescription> _cameras = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCameras());
  }

  /// Leaves the tracing surface for the AR chooser. Having traced is a natural
  /// moment to ask how it's going (the prompt is frequency-capped, so it rarely
  /// actually shows).
  void _leaveToHome() {
    Navigator.of(context).maybePop();
    FeedbackPrompter.maybePrompt(trigger: 'ar_traced');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _releaseCamera();
    } else if (state == AppLifecycleState.resumed && !_hasCamera) {
      _initCameras();
    }
  }

  void _releaseCamera() {
    final cam = _cameraController;
    if (cam == null) return;
    _cameraController = null;
    _flashlightOn = false;
    cam.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _initCameras() async {
    if (mounted && !_camerasLoading) setState(() => _camerasLoading = true);
    if (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      if (mounted) setState(() => _camerasLoading = false);
      return;
    }
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraError = 'No camera hardware found on this device';
            _camerasLoading = false;
          });
        }
        return;
      }
      await _initCameraController(_cameras[0]);
    } catch (e) {
      debugPrint('ArDrawingScreen: camera init failed: $e');
      if (mounted) {
        setState(() {
          _cameraError = 'Failed to access camera: $e';
          _camerasLoading = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() => _camerasLoading = false);
    }
  }

  Future<void> _initCameraController(CameraDescription camera) async {
    try {
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted || _disposed) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraError = null;
        _cameraController?.dispose();
        _cameraController = controller;
      });
    } catch (e) {
      debugPrint('ArDrawingScreen: controller init failed: $e');
      if (mounted) {
        setState(() {
          _cameraError = 'Camera unavailable: $e';
          _cameraController = null;
        });
      }
    }
  }

  bool get _hasCamera => _cameraController != null;

  void _onOpacityChanged(double value) => setState(() => _opacity = value);

  void _onLockToggle() => setState(() => _isLocked = !_isLocked);

  Future<void> _onCameraToggle() async {
    if (!_hasCamera) return;
    if (_cameras.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only one camera available'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    _cameraController?.dispose();
    _cameraController = null;
    if (mounted) setState(() {});

    _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;
    await _initCameraController(_cameras[_currentCameraIndex]);
  }

  Future<void> _onFlashlightToggle() async {
    if (!_hasCamera || _disposed) return;
    try {
      await _cameraController!.setFlashMode(
        _flashlightOn ? FlashMode.off : FlashMode.torch,
      );
      if (mounted) setState(() => _flashlightOn = !_flashlightOn);
    } catch (e) {
      debugPrint('ArDrawingScreen: flash toggle failed: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Live camera (or loading / "no camera" fallback) fills the screen.
            if (_camerasLoading)
              const Center(child: CircularProgressIndicator())
            else if (_hasCamera)
              CameraPreviewWidget(controller: _cameraController!)
            else
              CameraErrorWidget(message: _cameraError),

            // The chosen photo, centred and draggable/scalable.
            ArOverlayImage(
              opacity: _opacity,
              isLocked: _isLocked,
              onLockToggle: _onLockToggle,
              imagePath: widget.imagePath,
              presetSvgUrl: widget.presetSvgUrl,
            ),

            // Single floating Home button (replaces the old app bar).
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: _GlassHomeButton(
                    onTap: _leaveToHome,
                  ),
                ),
              ),
            ),

            // Opacity slider + camera / flash (Gallery & Presets removed).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BottomControls(
                opacity: _opacity,
                onOpacityChanged: _onOpacityChanged,
                onCameraToggle: _onCameraToggle,
                onFlashlightToggle: _onFlashlightToggle,
                flashlightOn: _flashlightOn,
                hasCamera: _hasCamera,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round frosted-glass Home button that floats over the camera feed.
class _GlassHomeButton extends StatelessWidget {
  const _GlassHomeButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Material(
          color: Colors.black.withValues(alpha: 0.35),
          shape: const CircleBorder(
            side: BorderSide(color: Colors.white24),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: const Tooltip(
              message: 'Home',
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.home_rounded, color: Colors.white, size: 24),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
