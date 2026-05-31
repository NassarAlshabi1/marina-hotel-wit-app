import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../services/performance_optimizer.dart';

class OptimizedImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const OptimizedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final optimizer = PerformanceOptimizer();

    if (imageUrl.endsWith('.svg')) {
      return SvgPicture.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        placeholderBuilder: (context) => placeholder ?? const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      // تحسين الذاكرة للأجهزة الضعيفة عبر تحديد حجم الصورة في الذاكرة
      memCacheWidth: optimizer.currentMode == PerformanceMode.low ? 200 : 500,
      maxWidthDiskCache: optimizer.currentMode == PerformanceMode.low ? 400 : 1000,
      placeholder: (context, url) => placeholder ?? Container(
        color: Colors.grey[200],
        child: const Center(child: Icon(Icons.image, color: Colors.grey)),
      ),
      errorWidget: (context, url, error) => errorWidget ?? Container(
        color: Colors.grey[200],
        child: const Center(child: Icon(Icons.error_outline, color: Colors.red)),
      ),
    );
  }
}
