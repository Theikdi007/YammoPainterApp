import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraErrorWidget extends StatelessWidget {
  const CameraErrorWidget({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off, color: Colors.grey.shade600, size: 48),
              const SizedBox(height: 16),
              Text(
                message ?? 'Camera not available',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CameraPreviewWidget extends StatelessWidget {
  const CameraPreviewWidget({
    super.key,
    required this.controller,
  });

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.previewSize?.width ?? 1080,
            height: controller.value.previewSize?.height ?? 1920,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}
